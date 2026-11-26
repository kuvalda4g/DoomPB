; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-06 used-wall-texture cache. Reads already-resolved TextureCatalog names
; selected by the existing M3-05 WallSpanPlan tier flags, composes only unique
; catalog indexes through the existing M2 TextureCompose, and owns every
; resulting row-major pixel/mask plane for the static frame.
;
; Source correspondence: r_data.c R_InitTextures (textureheight/widthmask),
; R_GenerateLookup/R_GenerateComposite/R_GetColumn (material identity) and
; r_segs.c R_StoreWallRange texturetranslation/sidedef selection. Composition
; itself remains M2-03 TextureCompose; this module never re-implements patch
; decoding or a second texture engine.
;
; Selection contract:
;   - side 0/1 of the published span/plan selects the matching SIDEDEF;
;   - field 0=top, 1=bottom, 2=middle; canonical eight-byte slot names;
;   - a canonical unused "-"/all-NUL slot is NoTexture, and a resolved catalog
;     index 0 is the original NoTexture quirk; neither is composed;
;   - top/bottom are requested only when the M3-05 plan tier flag is true and
;     the field resolves present (nonzero catalog index);
;   - one-sided middle is requested only when MiddleTier is true;
;   - a two-sided middle slot resolving nonzero is a masked midtexture. It is
;     detected and counted, but deliberately NOT composed or painted because
;     vanilla back-to-front masked drawing (`maskedtexturecol`, drawseg order)
;     remains deferred to M4;
;   - malformed/noncanonical names and missing catalog entries fail with
;     contextual diagnostics; no invented index is used.
;
; Uniqueness/cache lifetime:
;   - one entry per distinct catalog texture index referenced by visible
;     painted tiers; repeated span/tier references reuse that entry (counted);
;   - composed planes are owned by each entry's embedded TextureImage; entries
;     never shallow-copy an owning TextureImage from another slot and no
;     CopyMemory of composed records occurs;
;   - composition happens only while the WAD is open and the catalog resolved;
;     after WADClose/reopen callers MUST invalidate/re-resolve and rebuild the
;     cache before composing again (no automatic stale-lump detection);
;   - Reset frees every entry image exactly once, then the entry array; it is
;     idempotent and transactional Build failure leaves the cache empty and
;     reusable. No WAD/map/catalog pointer is retained after composition.
;   - texture metadata: Width, Height, exact vanilla WidthMask, ShortHeight
;     (height<128), OpaqueCount; image width/dims are cross-checked with the
;     catalog definition and R_InitTextures mask generation, never modulo width.
;
; Budget/allocation policy:
;   - unique index collection uses one bounded temporary Long array; entries are
;     pre-sized to the exact unique count, catalog indexes are copied into the
;     entries while the temp array exists, then the temp array is released;
;   - dimensions/patch composition are already checked by M2; a total checked
;     pixel+mask byte budget is applied before any image compose;
;   - caller-level allocations (temp + entries + two owned planes per composed
;     image) are counted. Transient patch raw buffers inside TextureCompose are
;     released by that module on every path and are not retained.
;   - no per-column/per-pixel cache I/O or allocation; image pointers borrowed
;     by span preparation/draw only for the duration of that draw.
;   - no per-column reads/composes/allocations: cache accessors are used only
;     by span preparation outside per-column loops.
;
; Borrowed image access note: WallTextureCacheImagePtr returns a read-only .i
; address of an entry's embedded TextureImage for the duration of a draw only.
; The caller must not copy the owning structure, reset it, or retain the pointer
; after frame/reset/reopen. Tests may read planes through this ephemeral accessor
; but never own/free them.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLTEXTURECACHE_PBI, #PB_Constant) = 0

#DOOMPB_WALLTEXTURECACHE_PBI = 1

XIncludeFile "WallTextureMapping.pbi"
XIncludeFile "../Graphics/Texture.pbi"
XIncludeFile "../Graphics/Palette.pbi"
XIncludeFile "../Graphics/Patch.pbi"
XIncludeFile "../WAD/WAD.pbi"
XIncludeFile "WallLighting.pbi"

#WALLTEXCACHE_Magic = $57544431
#WALLTEXCACHE_NoTexture = -1
#WALLTEXCACHE_MaxUniqueTextures = 4096
#WALLTEXCACHE_MaxTempBytes = 1048576
#WALLTEXCACHE_MaxEntriesBytes = 67108864
#WALLTEXCACHE_MaxPlaneBytes = 67108864
#WALLTEXCACHE_MaxPlans = 200000
#WALLTEXCACHE_MaxDimension = #WALLTEX_MaxTextureDimension
#WALLTEXCACHE_ExactSourceRows = #WALLTEX_ExactSourceRows

Structure WallTextureEntry
  CatalogIndex.l
  Width.l
  Height.l
  WidthMask.l
  ShortHeight.l
  OpaqueCount.q
  Image.TextureImage
EndStructure

Structure WallTextureCache
  Magic.l
  Ready.l
  Count.l
  Capacity.l
  *Entries.WallTextureEntry
  RequestedReferences.l
  ReusedReferences.l
  MaskedMidSpans.l
  ShortTextures.l
  Allocations.l
  TempBytes.q
  PlaneBytes.q
  PeakBytes.q
EndStructure

Global gWallTextureCache_LastError.s = ""

Procedure WallTextureCacheSetError(Message.s)
  gWallTextureCache_LastError = Message
EndProcedure

Procedure.s WallTextureCacheLastError()
  ProcedureReturn gWallTextureCache_LastError
EndProcedure

Procedure.i WallTextureCacheIsValid(*Cache.WallTextureCache)
  ProcedureReturn Bool(*Cache <> 0 And *Cache\Magic = #WALLTEXCACHE_Magic)
EndProcedure

; ---------------------------------------------------------------------------
; Existing-plan sidedef selection (no second geometry calculation)
; ---------------------------------------------------------------------------

; Reads the existing plan's Linedef/Side and selects the matching SIDEDEF.
; The plan is the M3-05 published numeric authority; this only re-reads raw
; sidedef/linedef fields from the unchanged validated level.
Procedure.i WallTexturePlanSidedefChecked(*Level.MapLevel, *Plan.WallSpanPlan,
                                          *SideIndex.Long)
  Protected lineIndex.l = 0
  Protected sideIndex.l = 0
  Protected selectedSide.l = 0
  Protected sector.l = 0
  Protected lineFlags.l = 0
  Protected lineSpecial.l = 0
  Protected lineTag.l = 0
  Protected side0.l = 0
  Protected side1.l = 0

  WallTextureCacheSetError("")
  If *SideIndex = 0
    WallTextureCacheSetError("WallTexturePlanSidedefChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallTextureCacheSetError("Wall texture plan sidedef: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    WallTextureCacheSetError("Wall texture plan sidedef: span plan is not ready.")
    ProcedureReturn #False
  EndIf

  lineIndex = *Plan\Linedef
  sideIndex = *Plan\Side
  If lineIndex < 0 Or lineIndex >= *Level\Linedefs\Count
    WallTextureCacheSetError("Wall texture plan sidedef: linedef index is invalid: " + Str(lineIndex) + ".")
    ProcedureReturn #False
  EndIf
  If sideIndex <> 0 And sideIndex <> 1
    WallTextureCacheSetError("Wall texture plan sidedef: plan side is invalid: " + Str(sideIndex) + ".")
    ProcedureReturn #False
  EndIf
  If MapLinedefsGet(@*Level\Linedefs, lineIndex, 0, 0, @lineFlags, @lineSpecial,
                    @lineTag, @side0, @side1) = #False
    WallTextureCacheSetError("Wall texture plan sidedef: cannot read linedef " + Str(lineIndex) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If sideIndex = 0
    selectedSide = side0
  Else
    selectedSide = side1
  EndIf
  If selectedSide < 0 Or selectedSide >= *Level\Sidedefs\Count
    WallTextureCacheSetError("Wall texture plan sidedef: seg side selects a missing sidedef: " + Str(selectedSide) + ".")
    ProcedureReturn #False
  EndIf
  If MapSidedefsGet(@*Level\Sidedefs, selectedSide, 0, 0, @sector) = #False
    WallTextureCacheSetError("Wall texture plan sidedef: cannot read sidedef " + Str(selectedSide) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If sector <> *Plan\FrontSector
    WallTextureCacheSetError("Wall texture plan sidedef: selected sector disagrees with the published front sector.")
    ProcedureReturn #False
  EndIf

  *SideIndex\l = selectedSide
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Texture slot resolution by field (0 top, 1 bottom, 2 middle)
; ---------------------------------------------------------------------------

; Canonical slot read + existing first-match TextureCatalogFindName. Returns
; Present=0 / CatalogIndex=-1 for canonical unused "-"/all-NUL and for a genuine
; catalog index 0 NoTexture; a valid nonzero definition yields present=1 and its
; index. Malformed/missing names are failures with field/sidedef context.
Procedure.i WallTextureResolvedFieldChecked(*Level.MapLevel,
                                            *Textures.TextureCatalog,
                                            SideIndex.l, Field.l,
                                            *Present.Long, *CatalogIndex.Long)
  Protected status.i
  Protected nameSlot.WallSlotNameOut
  Protected resolvedIndex.i

  WallTextureCacheSetError("")
  If *Present = 0 Or *CatalogIndex = 0
    WallTextureCacheSetError("WallTextureResolvedFieldChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallTextureCacheSetError("Wall texture field resolution: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Textures = 0 Or *Textures\Magic <> #TEXTURE_CatalogMagic
    WallTextureCacheSetError("Wall texture field resolution: texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If SideIndex < 0 Or SideIndex >= *Level\Sidedefs\Count
    WallTextureCacheSetError("Wall texture field resolution: sidedef index is out of range: " + Str(SideIndex) + ".")
    ProcedureReturn #False
  EndIf
  If Field < 0 Or Field > 2
    WallTextureCacheSetError("Wall texture field resolution: field must be 0 top, 1 bottom or 2 middle: " + Str(Field) + ".")
    ProcedureReturn #False
  EndIf

  status = WallWallSlotStatus(*Level, SideIndex, Field, @nameSlot)
  If status = 3
    WallTextureCacheSetError("Wall texture field resolution: sidedef " + Str(SideIndex) +
                             " field " + Str(Field) + " raw slot read failed.")
    ProcedureReturn #False
  EndIf
  If status = 2
    WallTextureCacheSetError("Wall texture field resolution: sidedef " + Str(SideIndex) +
                             " field " + Str(Field) + " name slot is noncanonical (embedded NUL/nonprintable).")
    ProcedureReturn #False
  EndIf
  If status = 1
    *Present\l = 0
    *CatalogIndex\l = #WALLTEXCACHE_NoTexture
    gWallTextureCache_LastError = ""
    ProcedureReturn #True
  EndIf

  resolvedIndex = TextureCatalogFindName(*Textures, nameSlot\Value)
  If resolvedIndex < 0
    WallTextureCacheSetError("Wall texture field resolution: sidedef " + Str(SideIndex) +
                             " field " + Str(Field) + " texture is not found in the catalog: " +
                             nameSlot\Value)
    ProcedureReturn #False
  EndIf
  If resolvedIndex = 0
    ; Original texturetranslation numeric 0 is the NoTexture quirk, even when a
    ; genuine first definition uses that index.
    *Present\l = 0
    *CatalogIndex\l = #WALLTEXCACHE_NoTexture
  Else
    *Present\l = 1
    *CatalogIndex\l = resolvedIndex
  EndIf
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Ownership / reset
; ---------------------------------------------------------------------------

Procedure.i WallTextureCacheEntryReset(*Entry.WallTextureEntry)
  If *Entry = 0
    WallTextureCacheSetError("Wall texture entry pointer is null.")
    ProcedureReturn #False
  EndIf
  TextureImageReset(@*Entry\Image)
  FillMemory(*Entry, Int(SizeOf(WallTextureEntry)), 0)
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; Idempotent empty reusable cache. Recognized Magic frees each entry image once
; and the entry array; zero-initialized caller structure is accepted. Unexplained
; pointers or inconsistent count/capacity are rejected rather than freed.
Procedure.i WallTextureCacheReset(*Cache.WallTextureCache)
  Protected entryIndex.i

  If *Cache = 0
    WallTextureCacheSetError("Wall texture cache pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Cache\Magic = #WALLTEXCACHE_Magic
    If *Cache\Entries <> 0
      If *Cache\Count < 0 Or *Cache\Capacity < 0 Or
         *Cache\Count > *Cache\Capacity Or *Cache\Capacity > #WALLTEXCACHE_MaxUniqueTextures
        WallTextureCacheSetError("Wall texture cache count/capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      For entryIndex = 0 To *Cache\Capacity - 1
        If WallTextureCacheEntryReset(*Cache\Entries + entryIndex * SizeOf(WallTextureEntry)) = #False
          ProcedureReturn #False
        EndIf
      Next
      FreeMemory(*Cache\Entries)
    EndIf
  ElseIf *Cache\Magic <> 0
    WallTextureCacheSetError("Wall texture cache has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Cache\Entries <> 0
    WallTextureCacheSetError("Wall texture cache has an unexplained entry pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Cache, Int(SizeOf(WallTextureCache)), 0)
  *Cache\Magic = #WALLTEXCACHE_Magic
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Used unique collection and composition
; ---------------------------------------------------------------------------

Procedure.i WallTextureCacheBuild(*Level.MapLevel, *Textures.TextureCatalog,
                                  *Plans.WallSpanPlan, PlanCount.l,
                                  *Cache.WallTextureCache)
  Protected tempCapacity.l
  Protected tempBytes.q
  Protected tempMemory.i = 0
  Protected entriesMemory.i = 0
  Protected entriesBytes.q
  Protected uniqueCount.l = 0
  Protected entryIndex.i
  Protected planIndex.i
  Protected planSidedef.l = 0
  Protected present.l = 0
  Protected catalogIndex.l = #WALLTEXCACHE_NoTexture
  Protected requestedReferences.l = 0
  Protected reusedReferences.l = 0
  Protected maskedMidSpans.l = 0
  Protected composedTextures.l = 0
  Protected shortTextures.l = 0
  Protected allocations.l = 0
  Protected expectedPlaneBytes.q = 0
  Protected planeBytes.q = 0
  Protected peakBytes.q = 0
  Protected width.l = 0
  Protected height.l = 0
  Protected patchCount.l = 0
  Protected pixelCount.q
  Protected widthMask.l = 0
  Protected *plan.WallSpanPlan
  Protected *entry.WallTextureEntry
  Protected alreadyPresent.l = 0
  Protected searchIndex.i
  Protected failureText.s = ""
  Protected savedFailureText.s = ""

  WallTextureCacheSetError("")
  If *Cache = 0
    WallTextureCacheSetError("WallTextureCacheBuild: cache pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallTextureCacheReset(*Cache) = #False
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallTextureCacheSetError("Wall texture cache: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Textures = 0 Or *Textures\Magic <> #TEXTURE_CatalogMagic
    WallTextureCacheSetError("Wall texture cache: texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If PlanCount < 0 Or PlanCount > #WALLTEXCACHE_MaxPlans
    WallTextureCacheSetError("Wall texture cache: plan count is outside 0.." + Str(#WALLTEXCACHE_MaxPlans) + ": " + Str(PlanCount) + ".")
    ProcedureReturn #False
  EndIf
  If PlanCount > 0 And *Plans = 0
    WallTextureCacheSetError("Wall texture cache: plan array pointer is null for a nonzero plan count.")
    ProcedureReturn #False
  EndIf

  ; First pass: collect only distinct catalog indexes used by active painted
  ; tiers; detect two-sided masked middles separately; no composition yet.
  tempCapacity = TextureCatalogCount(*Textures)
  If tempCapacity < 0
    WallTextureCacheSetError("Wall texture cache: catalog count read failed.")
    ProcedureReturn #False
  EndIf
  tempBytes = Int(tempCapacity) * SizeOf(Long)
  If tempBytes < 0 Or tempBytes > #WALLTEXCACHE_MaxTempBytes
    WallTextureCacheSetError("Wall texture cache uniqueness temp array bytes " + Str(tempBytes) +
                             " exceed the checked budget " + Str(#WALLTEXCACHE_MaxTempBytes) + ".")
    ProcedureReturn #False
  EndIf
  If tempCapacity > 0
    tempMemory = AllocateMemory(tempBytes)
    If tempMemory = 0
      WallTextureCacheSetError("Out of memory for wall texture uniqueness temp array.")
      ProcedureReturn #False
    EndIf
    FillMemory(tempMemory, Int(tempBytes), $FF)
    allocations + 1
  EndIf

  For planIndex = 0 To PlanCount - 1
    *plan = *Plans + planIndex * SizeOf(WallSpanPlan)
    If WallSpanPlanIsReady(*plan) = #False
      failureText = "Wall texture cache plan " + Str(planIndex) + " is not ready."
      Goto WallTextureCacheFailure
    EndIf
    If WallTexturePlanSidedefChecked(*Level, *plan, @planSidedef) = #False
      failureText = "Wall texture cache plan " + Str(planIndex) + " sidedef failed: " + WallTextureCacheLastError()
      Goto WallTextureCacheFailure
    EndIf

    If *plan\TopTier <> 0
      requestedReferences + 1
      If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 0,
                                         @present, @catalogIndex) = #False
        failureText = "Wall texture cache plan " + Str(planIndex) + " top field failed: " + WallTextureCacheLastError()
        Goto WallTextureCacheFailure
      EndIf
      If present = 0
        failureText = "Wall texture cache plan " + Str(planIndex) + " top tier is true but its top slot resolves absent."
        Goto WallTextureCacheFailure
      EndIf
      alreadyPresent = #False
      For searchIndex = 0 To uniqueCount - 1
        If PeekL(tempMemory + searchIndex * SizeOf(Long)) = catalogIndex
          alreadyPresent = #True
          Break
        EndIf
      Next
      If alreadyPresent
        reusedReferences + 1
      Else
        If uniqueCount >= tempCapacity Or uniqueCount >= #WALLTEXCACHE_MaxUniqueTextures
          failureText = "Wall texture cache unique texture count exceeds checked capacity/budget."
          Goto WallTextureCacheFailure
        EndIf
        PokeL(tempMemory + uniqueCount * SizeOf(Long), catalogIndex)
        uniqueCount + 1
      EndIf
    EndIf

    If *plan\BottomTier <> 0
      requestedReferences + 1
      If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 1,
                                         @present, @catalogIndex) = #False
        failureText = "Wall texture cache plan " + Str(planIndex) + " bottom field failed: " + WallTextureCacheLastError()
        Goto WallTextureCacheFailure
      EndIf
      If present = 0
        failureText = "Wall texture cache plan " + Str(planIndex) + " bottom tier is true but its bottom slot resolves absent."
        Goto WallTextureCacheFailure
      EndIf
      alreadyPresent = #False
      For searchIndex = 0 To uniqueCount - 1
        If PeekL(tempMemory + searchIndex * SizeOf(Long)) = catalogIndex
          alreadyPresent = #True
          Break
        EndIf
      Next
      If alreadyPresent
        reusedReferences + 1
      Else
        If uniqueCount >= tempCapacity Or uniqueCount >= #WALLTEXCACHE_MaxUniqueTextures
          failureText = "Wall texture cache unique texture count exceeds checked capacity/budget."
          Goto WallTextureCacheFailure
        EndIf
        PokeL(tempMemory + uniqueCount * SizeOf(Long), catalogIndex)
        uniqueCount + 1
      EndIf
    EndIf

    If *plan\MiddleTier <> 0
      requestedReferences + 1
      If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 2,
                                         @present, @catalogIndex) = #False
        failureText = "Wall texture cache plan " + Str(planIndex) + " middle field failed: " + WallTextureCacheLastError()
        Goto WallTextureCacheFailure
      EndIf
      If present = 0
        failureText = "Wall texture cache plan " + Str(planIndex) + " one-sided middle tier is true but its middle slot resolves absent."
        Goto WallTextureCacheFailure
      EndIf
      alreadyPresent = #False
      For searchIndex = 0 To uniqueCount - 1
        If PeekL(tempMemory + searchIndex * SizeOf(Long)) = catalogIndex
          alreadyPresent = #True
          Break
        EndIf
      Next
      If alreadyPresent
        reusedReferences + 1
      Else
        If uniqueCount >= tempCapacity Or uniqueCount >= #WALLTEXCACHE_MaxUniqueTextures
          failureText = "Wall texture cache unique texture count exceeds checked capacity/budget."
          Goto WallTextureCacheFailure
        EndIf
        PokeL(tempMemory + uniqueCount * SizeOf(Long), catalogIndex)
        uniqueCount + 1
      EndIf
    EndIf

    If *plan\TwoSided <> 0
      If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 2,
                                         @present, @catalogIndex) = #False
        failureText = "Wall texture cache plan " + Str(planIndex) + " masked middle field failed: " + WallTextureCacheLastError()
        Goto WallTextureCacheFailure
      EndIf
      If present <> 0
        maskedMidSpans + 1
      EndIf
    EndIf
  Next

  If uniqueCount > #WALLTEXCACHE_MaxUniqueTextures
    failureText = "Wall texture cache unique count exceeds the checked cap."
    Goto WallTextureCacheFailure
  EndIf

  ; Pre-budget all unique dimensions/pixel plane bytes through M2 properties.
  For searchIndex = 0 To uniqueCount - 1
    catalogIndex = PeekL(tempMemory + searchIndex * SizeOf(Long))
    If TextureCatalogGetProperties(*Textures, Int(catalogIndex), @width, @height,
                                   0, 0, @patchCount, 0) = #False
      failureText = "Wall texture cache cannot read properties for catalog texture " + Str(catalogIndex) + ": " + TextureDefsLastError()
      Goto WallTextureCacheFailure
    EndIf
    If width <= 0 Or width > #WALLTEXCACHE_MaxDimension Or
       height <= 0 Or height > #WALLTEXCACHE_MaxDimension
      failureText = "Wall texture cache catalog texture " + Str(catalogIndex) + " has invalid dimensions."
      Goto WallTextureCacheFailure
    EndIf
    pixelCount.q = Int(width) * Int(height)
    If pixelCount <= 0 Or pixelCount > #TEXTURE_MaxOutputPixels
      failureText = "Wall texture cache catalog texture " + Str(catalogIndex) + " pixel count exceeds the texture budget."
      Goto WallTextureCacheFailure
    EndIf
    expectedPlaneBytes = expectedPlaneBytes + pixelCount * 2
    If expectedPlaneBytes > #WALLTEXCACHE_MaxPlaneBytes
      failureText = "Wall texture cache composed pixel+mask plane bytes " + Str(expectedPlaneBytes) +
                    " exceed the checked budget " + Str(#WALLTEXCACHE_MaxPlaneBytes) + "."
      Goto WallTextureCacheFailure
    EndIf
  Next

  ; Exact-size entry array while the uniqueness temp array still exists.
  If uniqueCount > 0
    entriesBytes = Int(uniqueCount) * SizeOf(WallTextureEntry)
    If entriesBytes <= 0 Or entriesBytes > #WALLTEXCACHE_MaxEntriesBytes
      failureText = "Wall texture cache entry array bytes " + Str(entriesBytes) +
                    " exceed the checked budget " + Str(#WALLTEXCACHE_MaxEntriesBytes) + "."
      Goto WallTextureCacheFailure
    EndIf
    entriesMemory = AllocateMemory(entriesBytes)
    If entriesMemory = 0
      failureText = "Out of memory for wall texture cache entry array."
      Goto WallTextureCacheFailure
    EndIf
    FillMemory(entriesMemory, Int(entriesBytes), 0)
    allocations + 1
    peakBytes = Int(tempBytes) + Int(entriesBytes)
    For entryIndex = 0 To uniqueCount - 1
      *entry = entriesMemory + entryIndex * SizeOf(WallTextureEntry)
      *entry\CatalogIndex = PeekL(tempMemory + entryIndex * SizeOf(Long))
    Next
  Else
    entriesBytes = 0
    peakBytes = Int(tempBytes)
  EndIf

  If tempMemory <> 0
    FreeMemory(tempMemory)
    tempMemory = 0
  EndIf

  *Cache\Entries = entriesMemory
  *Cache\Capacity = uniqueCount
  *Cache\Count = 0

  ; Composition only while the current WAD session is open.
  If uniqueCount > 0 And WADIsOpen() = #False
    failureText = "Wall texture cache composition requires the resolved catalog's current WAD to be open."
    Goto WallTextureCacheFailure
  EndIf

  For entryIndex = 0 To uniqueCount - 1
    *entry = *Cache\Entries + entryIndex * SizeOf(WallTextureEntry)
    catalogIndex = *entry\CatalogIndex
    If catalogIndex < 0 Or catalogIndex >= TextureCatalogCount(*Textures)
      failureText = "Wall texture cache entry catalog index is invalid: " + Str(catalogIndex) + "."
      Goto WallTextureCacheFailure
    EndIf
    If TextureCatalogGetProperties(*Textures, Int(catalogIndex), @width, @height,
                                   0, 0, @patchCount, 0) = #False
      failureText = "Wall texture cache entry properties read failed: " + TextureDefsLastError()
      Goto WallTextureCacheFailure
    EndIf
    If TextureCompose(*Textures, Int(catalogIndex), @*entry\Image) = #False
      failureText = "Wall texture cache compose failed for catalog texture " + Str(catalogIndex) + ": " + TextureLastError()
      Goto WallTextureCacheFailure
    EndIf
    If *entry\Image\Magic <> #TEXTURE_ImageMagic Or
       *entry\Image\Width <> width Or *entry\Image\Height <> height Or
       *entry\Image\Pixels = 0 Or *entry\Image\Mask = 0
      failureText = "Wall texture cache composed image metadata disagrees with the catalog definition."
      Goto WallTextureCacheFailure
    EndIf
    If WallTextureWidthMaskChecked(width, @widthMask) = #False
      failureText = "Wall texture cache width-mask generation failed: " + WallTextureMappingLastError()
      Goto WallTextureCacheFailure
    EndIf
    If widthMask >= width
      failureText = "Wall texture cache width mask is not inside the texture width."
      Goto WallTextureCacheFailure
    EndIf

    *entry\Width = width
    *entry\Height = height
    *entry\WidthMask = widthMask
    *entry\ShortHeight = Bool(height < #WALLTEXCACHE_ExactSourceRows)
    *entry\OpaqueCount = TextureImageOpaqueCount(@*entry\Image)
    composedTextures + 1
    allocations = allocations + 2
    If height < #WALLTEXCACHE_ExactSourceRows
      shortTextures + 1
    EndIf
    planeBytes = planeBytes + Int(*entry\Image\PixelCount) * 2
    If planeBytes > #WALLTEXCACHE_MaxPlaneBytes
      failureText = "Wall texture cache retained plane bytes exceed the checked budget."
      Goto WallTextureCacheFailure
    EndIf
  Next
  peakBytes = peakBytes + Int(planeBytes)

  *Cache\RequestedReferences = requestedReferences
  *Cache\ReusedReferences = reusedReferences
  *Cache\MaskedMidSpans = maskedMidSpans
  *Cache\ShortTextures = shortTextures
  *Cache\Allocations = allocations
  *Cache\TempBytes = Int(tempBytes)
  *Cache\PlaneBytes = planeBytes
  *Cache\PeakBytes = peakBytes
  *Cache\Count = composedTextures
  *Cache\Ready = 1
  gWallTextureCache_LastError = ""
  ProcedureReturn #True

  WallTextureCacheFailure:
  If failureText = ""
    failureText = WallTextureCacheLastError()
  EndIf
  If tempMemory <> 0
    FreeMemory(tempMemory)
    tempMemory = 0
  EndIf
  WallTextureCacheReset(*Cache)
  WallTextureCacheSetError(failureText)
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Read-only accessors
; ---------------------------------------------------------------------------

Procedure.i WallTextureCacheCount(*Cache.WallTextureCache)
  If WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture cache is not initialized.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn *Cache\Count
EndProcedure

; First matching composed entry for a catalog texture index; -1 when absent.
Procedure.i WallTextureCacheFindIndex(*Cache.WallTextureCache, CatalogIndex.l)
  Protected entryIndex.i
  Protected *entry.WallTextureEntry

  If WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture cache is not initialized.")
    ProcedureReturn -1
  EndIf
  If CatalogIndex < 0
    WallTextureCacheSetError("Wall texture cache lookup index is negative: " + Str(CatalogIndex) + ".")
    ProcedureReturn -1
  EndIf
  For entryIndex = 0 To *Cache\Count - 1
    *entry = *Cache\Entries + entryIndex * SizeOf(WallTextureEntry)
    If *entry\CatalogIndex = CatalogIndex
      gWallTextureCache_LastError = ""
      ProcedureReturn entryIndex
    EndIf
  Next
  WallTextureCacheSetError("Wall texture cache has no composed entry for catalog texture " + Str(CatalogIndex) + ".")
  ProcedureReturn -1
EndProcedure

Procedure.i WallTextureCacheEntryGet(*Cache.WallTextureCache, EntryIndex.l,
                                     *CatalogIndex.Long, *Width.Long,
                                     *Height.Long, *WidthMask.Long,
                                     *ShortHeight.Long, *OpaqueCount.Quad,
                                     *ImagePixelCount.Quad)
  Protected *entry.WallTextureEntry

  If WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture cache is not initialized.")
    ProcedureReturn #False
  EndIf
  If EntryIndex < 0 Or EntryIndex >= *Cache\Count Or *Cache\Entries = 0
    WallTextureCacheSetError("Wall texture cache entry index is out of range: " + Str(EntryIndex) + ".")
    ProcedureReturn #False
  EndIf
  *entry = *Cache\Entries + EntryIndex * SizeOf(WallTextureEntry)
  If *entry\Image\Magic <> #TEXTURE_ImageMagic
    WallTextureCacheSetError("Wall texture cache entry image is not valid.")
    ProcedureReturn #False
  EndIf
  If *CatalogIndex <> 0
    PokeL(*CatalogIndex, *entry\CatalogIndex)
  EndIf
  If *Width <> 0
    PokeL(*Width, *entry\Width)
  EndIf
  If *Height <> 0
    PokeL(*Height, *entry\Height)
  EndIf
  If *WidthMask <> 0
    PokeL(*WidthMask, *entry\WidthMask)
  EndIf
  If *ShortHeight <> 0
    PokeL(*ShortHeight, *entry\ShortHeight)
  EndIf
  If *OpaqueCount <> 0
    PokeQ(*OpaqueCount, *entry\OpaqueCount)
  EndIf
  If *ImagePixelCount <> 0
    PokeQ(*ImagePixelCount, *entry\Image\PixelCount)
  EndIf
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; Borrowed read-only image address for samples/hashes during one draw. The
; cache owns/resets it; caller must not copy the struct or retain the pointer.
Procedure.i WallTextureCacheImagePtr(*Cache.WallTextureCache, EntryIndex.l)
  Protected *entry.WallTextureEntry

  If WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture cache is not initialized.")
    ProcedureReturn 0
  EndIf
  If EntryIndex < 0 Or EntryIndex >= *Cache\Count Or *Cache\Entries = 0
    WallTextureCacheSetError("Wall texture cache image pointer index is out of range: " + Str(EntryIndex) + ".")
    ProcedureReturn 0
  EndIf
  *entry = *Cache\Entries + EntryIndex * SizeOf(WallTextureEntry)
  If *entry\Image\Magic <> #TEXTURE_ImageMagic Or *entry\Image\Pixels = 0 Or *entry\Image\Mask = 0
    WallTextureCacheSetError("Wall texture cache entry image is not valid.")
    ProcedureReturn 0
  EndIf
  gWallTextureCache_LastError = ""
  ProcedureReturn @*entry\Image
EndProcedure

Procedure.i WallTextureCacheGetStats(*Cache.WallTextureCache,
                                     *Count.Long, *Capacity.Long,
                                     *RequestedReferences.Long,
                                     *ReusedReferences.Long, *MaskedMidSpans.Long,
                                     *ShortTextures.Long, *Allocations.Long,
                                     *TempBytes.Quad, *PlaneBytes.Quad,
                                     *PeakBytes.Quad)
  If WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture cache is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Count <> 0
    PokeL(*Count, *Cache\Count)
  EndIf
  If *Capacity <> 0
    PokeL(*Capacity, *Cache\Capacity)
  EndIf
  If *RequestedReferences <> 0
    PokeL(*RequestedReferences, *Cache\RequestedReferences)
  EndIf
  If *ReusedReferences <> 0
    PokeL(*ReusedReferences, *Cache\ReusedReferences)
  EndIf
  If *MaskedMidSpans <> 0
    PokeL(*MaskedMidSpans, *Cache\MaskedMidSpans)
  EndIf
  If *ShortTextures <> 0
    PokeL(*ShortTextures, *Cache\ShortTextures)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Cache\Allocations)
  EndIf
  If *TempBytes <> 0
    PokeQ(*TempBytes, *Cache\TempBytes)
  EndIf
  If *PlaneBytes <> 0
    PokeQ(*PlaneBytes, *Cache\PlaneBytes)
  EndIf
  If *PeakBytes <> 0
    PokeQ(*PeakBytes, *Cache\PeakBytes)
  EndIf
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Per-span textured material/pegging preparation (numeric only)
; ---------------------------------------------------------------------------

#WALLTEXSPAN_Magic = $57545331
#WALLTEXSPAN_NoTexture = #WALLTEXCACHE_NoTexture
#WALLTEXSPAN_NoCacheSlot = -1

Structure WallTextureSpanPlan
  Magic.l
  Ready.l
  SpanIndex.l
  Seg.l
  Linedef.l
  Side.l
  FrontSector.l
  BackSector.l
  FirstX.l
  LastX.l
  Kind.l
  MidTextureIndex.l
  TopTextureIndex.l
  BottomTextureIndex.l
  MaskedMidIndex.l
  MidCacheSlot.l
  TopCacheSlot.l
  BottomCacheSlot.l
  MidTextureMid.l
  TopTextureMid.l
  BottomTextureMid.l
  MidWidth.l
  TopWidth.l
  BottomWidth.l
  MidWidthMask.l
  TopWidthMask.l
  BottomWidthMask.l
  MidHeight.l
  TopHeight.l
  BottomHeight.l
  RawOffset.l
  CenterAngle.q
  LightNum.l
  MaskedMid.l
  HasPaintedTier.l
  SegmentTextured.l
EndStructure

Procedure.i WallTextureSpanPlanIsReady(*Plan.WallTextureSpanPlan)
  ProcedureReturn Bool(*Plan <> 0 And *Plan\Magic = #WALLTEXSPAN_Magic And
                        *Plan\Ready <> 0)
EndProcedure

Procedure.i WallTextureSpanPlanReset(*Plan.WallTextureSpanPlan)
  If *Plan = 0
    WallTextureCacheSetError("Wall texture span plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Plan\Magic <> 0 And *Plan\Magic <> #WALLTEXSPAN_Magic
    WallTextureCacheSetError("Wall texture span plan has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Plan, Int(SizeOf(WallTextureSpanPlan)), 0)
  *Plan\Magic = #WALLTEXSPAN_Magic
  ; Absent painted tiers carry the documented NoTexture/NoCacheSlot markers
  ; rather than misleading zero catalog/entry indexes; preparation replaces
  ; these for every painted or masked tier it decides.
  *Plan\MidTextureIndex = #WALLTEXSPAN_NoTexture
  *Plan\TopTextureIndex = #WALLTEXSPAN_NoTexture
  *Plan\BottomTextureIndex = #WALLTEXSPAN_NoTexture
  *Plan\MaskedMidIndex = #WALLTEXSPAN_NoTexture
  *Plan\MidCacheSlot = #WALLTEXSPAN_NoCacheSlot
  *Plan\TopCacheSlot = #WALLTEXSPAN_NoCacheSlot
  *Plan\BottomCacheSlot = #WALLTEXSPAN_NoCacheSlot
  gWallTextureCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; Derives the material selection, exact pegging texturemids, rw_offset/rw_centerangle,
; vanilla light row and width masks for one already-ready M3-05 WallSpanPlan.
; Reads only the unchanged map/sidedef/linedef/seg/vertex fields; no geometry
; formula is recomputed beyond the documented r_segs/r_draw helpers. Numeric
; copies only; no cache/map/texture/WAD pointer is retained in the plan.
Procedure.i WallTextureSpanPrepareChecked(*Level.MapLevel,
                                          *Textures.TextureCatalog,
                                          *Cache.WallTextureCache,
                                          *Plan.WallSpanPlan,
                                          ViewZFixed.l,
                                          *TexturePlan.WallTextureSpanPlan)
  Protected planSidedef.l = 0
  Protected segV1.l = 0
  Protected segV2.l = 0
  Protected segAngle.l = 0
  Protected segLine.l = 0
  Protected segSide.l = 0
  Protected segOffset.l = 0
  Protected vertexX1.l = 0
  Protected vertexY1.l = 0
  Protected vertexX2.l = 0
  Protected vertexY2.l = 0
  Protected lineFlags.l = 0
  Protected lineSpecial.l = 0
  Protected lineTag.l = 0
  Protected lineSide0.l = 0
  Protected lineSide1.l = 0
  Protected textureOffset.l = 0
  Protected rowOffset.l = 0
  Protected sideSector.l = 0
  Protected present.l = 0
  Protected catalogIndex.l = #WALLTEXSPAN_NoTexture
  Protected maskedPresent.l = 0
  Protected maskedIndex.l = #WALLTEXSPAN_NoTexture
  Protected catalogWidth.l = 0
  Protected catalogHeight.l = 0
  Protected patchCount.l = 0
  Protected entryCatalogIndex.l = 0
  Protected entryWidth.l = 0
  Protected entryHeight.l = 0
  Protected entryMask.l = 0
  Protected entryShort.l = 0
  Protected entryOpaque.q = 0
  Protected entryPixelCount.q = 0
  Protected recomputedMask.l = 0
  Protected fixedHeight.l = 0
  Protected textureMid.l = 0
  Protected rawOffset.l = 0
  Protected lightNum.l = 0
  Protected offsetCenter.q = 0
  Protected cacheSlot.i
  Protected midHeight.l = 0
  Protected topHeight.l = 0
  Protected bottomHeight.l = 0
  Protected failureText.s = ""
  Protected savedFailureText.s = ""

  WallTextureCacheSetError("")
  If *TexturePlan = 0
    WallTextureCacheSetError("WallTextureSpanPrepareChecked: output plan pointer is null.")
    ProcedureReturn #False
  EndIf
  If WallTextureSpanPlanReset(*TexturePlan) = #False
    ProcedureReturn #False
  EndIf
  If *Level = 0 Or MapLevelIsReady(*Level) = #False
    WallTextureCacheSetError("Wall texture span preparation: map level is not ready.")
    ProcedureReturn #False
  EndIf
  If *Textures = 0 Or *Textures\Magic <> #TEXTURE_CatalogMagic
    WallTextureCacheSetError("Wall texture span preparation: texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Cache = 0 Or WallTextureCacheIsValid(*Cache) = #False
    WallTextureCacheSetError("Wall texture span preparation: texture cache is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Plan = 0 Or WallSpanPlanIsReady(*Plan) = #False
    WallTextureCacheSetError("Wall texture span preparation: source span plan is not ready.")
    ProcedureReturn #False
  EndIf

  If WallTexturePlanSidedefChecked(*Level, *Plan, @planSidedef) = #False
    WallTextureCacheSetError("Wall texture span preparation sidedef failed: " + WallTextureCacheLastError())
    ProcedureReturn #False
  EndIf

  If MapSegsGet(@*Level\Segs, Int(*Plan\Seg), @segV1, @segV2, @segAngle, @segLine,
                @segSide, @segOffset) = #False
    WallTextureCacheSetError("Wall texture span preparation cannot read seg " + Str(*Plan\Seg) + ": " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If segLine <> *Plan\Linedef Or segSide <> *Plan\Side
    WallTextureCacheSetError("Wall texture span preparation seg fields disagree with the published plan.")
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, Int(segV1), @vertexX1, @vertexY1) = #False
    WallTextureCacheSetError("Wall texture span preparation cannot read seg v1 vertex: " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If MapVertexesGet(@*Level\Vertexes, Int(segV2), @vertexX2, @vertexY2) = #False
    WallTextureCacheSetError("Wall texture span preparation cannot read seg v2 vertex: " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If MapLinedefsGet(@*Level\Linedefs, Int(*Plan\Linedef), 0, 0, @lineFlags,
                    @lineSpecial, @lineTag, @lineSide0, @lineSide1) = #False
    WallTextureCacheSetError("Wall texture span preparation cannot read linedef: " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If MapSidedefsGet(@*Level\Sidedefs, planSidedef, @textureOffset, @rowOffset,
                    @sideSector) = #False
    WallTextureCacheSetError("Wall texture span preparation cannot read sidedef: " + MapDecodeLastError())
    ProcedureReturn #False
  EndIf
  If sideSector <> *Plan\FrontSector
    WallTextureCacheSetError("Wall texture span preparation selected sidedef sector disagrees with the plan.")
    ProcedureReturn #False
  EndIf

  If ViewZFixed < #FIXED_MIN Or ViewZFixed > #FIXED_MAX
    WallTextureCacheSetError("Wall texture span preparation viewz is outside signed fixed_t.")
    ProcedureReturn #False
  EndIf

  ; One-sided middle painted tier.
  If *Plan\MiddleTier <> 0
    If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 2,
                                       @present, @catalogIndex) = #False
      failureText = "Wall texture span preparation middle field failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If present = 0
      failureText = "Wall texture span middle tier is true but the middle slot resolves absent."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If TextureCatalogGetProperties(*Textures, Int(catalogIndex), @catalogWidth,
                                   @catalogHeight, 0, 0, @patchCount, 0) = #False
      failureText = "Wall texture span cannot read middle texture properties: " + TextureDefsLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    cacheSlot = WallTextureCacheFindIndex(*Cache, catalogIndex)
    If cacheSlot < 0
      failureText = "Wall texture span middle texture " + Str(catalogIndex) + " is not composed in the cache: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureCacheEntryGet(*Cache, cacheSlot, @entryCatalogIndex, @entryWidth,
                                @entryHeight, @entryMask, @entryShort,
                                @entryOpaque, @entryPixelCount) = #False
      failureText = "Wall texture span middle cache entry access failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If entryCatalogIndex <> catalogIndex Or entryWidth <> catalogWidth Or entryHeight <> catalogHeight
      failureText = "Wall texture span middle cache metadata disagrees with the catalog definition."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureWidthMaskChecked(entryWidth, @recomputedMask) = #False Or recomputedMask <> entryMask
      failureText = "Wall texture span middle width mask disagrees with the cache's R_InitTextures mask."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureHeightFixedChecked(entryHeight, @fixedHeight) = #False
      failureText = "Wall texture span middle height conversion failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureMidOneSidedChecked(*Plan\WorldTopRaw, *Plan\FrontFloorFixed,
                                     ViewZFixed, fixedHeight, rowOffset, lineFlags,
                                     @textureMid) = #False
      failureText = "Wall texture span one-sided middle pegging failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    *TexturePlan\MidTextureIndex = catalogIndex
    *TexturePlan\MidCacheSlot = cacheSlot
    *TexturePlan\MidTextureMid = textureMid
    *TexturePlan\MidWidth = entryWidth
    *TexturePlan\MidWidthMask = entryMask
    *TexturePlan\MidHeight = entryHeight
    midHeight = entryHeight
  EndIf

  ; Two-sided upper painted tier.
  If *Plan\TopTier <> 0
    If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 0,
                                       @present, @catalogIndex) = #False
      failureText = "Wall texture span preparation top field failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If present = 0
      failureText = "Wall texture span top tier is true but the top slot resolves absent."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If TextureCatalogGetProperties(*Textures, Int(catalogIndex), @catalogWidth,
                                   @catalogHeight, 0, 0, @patchCount, 0) = #False
      failureText = "Wall texture span cannot read top texture properties: " + TextureDefsLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    cacheSlot = WallTextureCacheFindIndex(*Cache, catalogIndex)
    If cacheSlot < 0
      failureText = "Wall texture span top texture " + Str(catalogIndex) + " is not composed in the cache."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureCacheEntryGet(*Cache, cacheSlot, @entryCatalogIndex, @entryWidth,
                                @entryHeight, @entryMask, @entryShort,
                                @entryOpaque, @entryPixelCount) = #False
      failureText = "Wall texture span top cache entry access failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If entryCatalogIndex <> catalogIndex Or entryWidth <> catalogWidth Or entryHeight <> catalogHeight
      failureText = "Wall texture span top cache metadata disagrees with the catalog definition."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureWidthMaskChecked(entryWidth, @recomputedMask) = #False Or recomputedMask <> entryMask
      failureText = "Wall texture span top width mask disagrees with the cache's R_InitTextures mask."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureHeightFixedChecked(entryHeight, @fixedHeight) = #False
      failureText = "Wall texture span top height conversion failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureMidUpperChecked(*Plan\WorldTopRaw, *Plan\BackCeilingFixed,
                                  ViewZFixed, fixedHeight, rowOffset, lineFlags,
                                  @textureMid) = #False
      failureText = "Wall texture span upper pegging failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    *TexturePlan\TopTextureIndex = catalogIndex
    *TexturePlan\TopCacheSlot = cacheSlot
    *TexturePlan\TopTextureMid = textureMid
    *TexturePlan\TopWidth = entryWidth
    *TexturePlan\TopWidthMask = entryMask
    *TexturePlan\TopHeight = entryHeight
    topHeight = entryHeight
  EndIf

  ; Two-sided lower painted tier.
  If *Plan\BottomTier <> 0
    If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 1,
                                       @present, @catalogIndex) = #False
      failureText = "Wall texture span preparation bottom field failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If present = 0
      failureText = "Wall texture span bottom tier is true but the bottom slot resolves absent."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If TextureCatalogGetProperties(*Textures, Int(catalogIndex), @catalogWidth,
                                   @catalogHeight, 0, 0, @patchCount, 0) = #False
      failureText = "Wall texture span cannot read bottom texture properties: " + TextureDefsLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    cacheSlot = WallTextureCacheFindIndex(*Cache, catalogIndex)
    If cacheSlot < 0
      failureText = "Wall texture span bottom texture " + Str(catalogIndex) + " is not composed in the cache."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureCacheEntryGet(*Cache, cacheSlot, @entryCatalogIndex, @entryWidth,
                                @entryHeight, @entryMask, @entryShort,
                                @entryOpaque, @entryPixelCount) = #False
      failureText = "Wall texture span bottom cache entry access failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If entryCatalogIndex <> catalogIndex Or entryWidth <> catalogWidth Or entryHeight <> catalogHeight
      failureText = "Wall texture span bottom cache metadata disagrees with the catalog definition."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureWidthMaskChecked(entryWidth, @recomputedMask) = #False Or recomputedMask <> entryMask
      failureText = "Wall texture span bottom width mask disagrees with the cache's R_InitTextures mask."
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallTextureMidLowerChecked(*Plan\WorldTopRaw, *Plan\WorldLowRaw,
                                  rowOffset, lineFlags, @textureMid) = #False
      failureText = "Wall texture span lower pegging failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    *TexturePlan\BottomTextureIndex = catalogIndex
    *TexturePlan\BottomCacheSlot = cacheSlot
    *TexturePlan\BottomTextureMid = textureMid
    *TexturePlan\BottomWidth = entryWidth
    *TexturePlan\BottomWidthMask = entryMask
    *TexturePlan\BottomHeight = entryHeight
    bottomHeight = entryHeight
  EndIf

  ; Two-sided masked middle: detect the original nonzero numeric condition, but
  ; never compose/paint it in M3-06. Its index is diagnostic metadata only.
  If *Plan\TwoSided <> 0
    If WallTextureResolvedFieldChecked(*Level, *Textures, planSidedef, 2,
                                       @maskedPresent, @maskedIndex) = #False
      failureText = "Wall texture span preparation masked middle field failed: " + WallTextureCacheLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    *TexturePlan\MaskedMidIndex = maskedIndex
    If maskedPresent <> 0
      *TexturePlan\MaskedMid = 1
    EndIf
  EndIf

  ; Segtextured = midtexture|toptexture|bottomtexture|maskedtexture; texture
  ; column/offset/centerangle/lighting are computed only in this source branch.
  If midHeight > 0 Or topHeight > 0 Or bottomHeight > 0 Or *TexturePlan\MaskedMid <> 0
    *TexturePlan\SegmentTextured = 1
    If WallTextureOffsetChecked(*Plan\ViewAngle, *Plan\NormalAngle,
                                *Plan\ReferenceAngle, *Plan\Hyp,
                                textureOffset, segOffset, @rawOffset,
                                @offsetCenter) = #False
      failureText = "Wall texture span rw_offset/rw_centerangle failed: " + WallTextureMappingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    If WallLightingLightNumChecked(*Plan\FrontLight, vertexY1, vertexY2,
                                   vertexX1, vertexX2, 0, @lightNum) = #False
      failureText = "Wall texture span light row selection failed: " + WallLightingLastError()
      Goto WallTextureSpanPrepareFailure
    EndIf
    *TexturePlan\RawOffset = rawOffset
    *TexturePlan\CenterAngle = offsetCenter
    *TexturePlan\LightNum = lightNum
  EndIf

  If midHeight > 0 Or topHeight > 0 Or bottomHeight > 0
    *TexturePlan\HasPaintedTier = 1
  EndIf

  *TexturePlan\SpanIndex = *Plan\SpanIndex
  *TexturePlan\Seg = *Plan\Seg
  *TexturePlan\Linedef = *Plan\Linedef
  *TexturePlan\Side = *Plan\Side
  *TexturePlan\FrontSector = *Plan\FrontSector
  *TexturePlan\BackSector = *Plan\BackSector
  *TexturePlan\FirstX = *Plan\FirstX
  *TexturePlan\LastX = *Plan\LastX
  *TexturePlan\Kind = *Plan\Kind
  *TexturePlan\Ready = 1
  gWallTextureCache_LastError = ""
  ProcedureReturn #True

  WallTextureSpanPrepareFailure:
  If failureText = ""
    failureText = WallTextureCacheLastError()
  EndIf
  WallTextureSpanPlanReset(*TexturePlan)
  WallTextureCacheSetError(failureText)
  ProcedureReturn #False
EndProcedure

CompilerEndIf
