; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M4-01 owned flat cache from M2 FlatCatalog/FlatLoad. Loads only the unique 64x64
; FLAT resources actually referenced by non-sky visplanes that carry at least one
; marked row band; sky identity is skipped and never decoded as a 4096-byte flat.
;
; Vanilla dependency: r_plane.c R_DrawPlanes caches `firstflat+
; flattranslation[pl->picnum]` for regular planes only. DoomPB keys the cache by
; resolved FlatCatalog index (last-duplicate catalog resolution from M2); index 0
; is a legitimate ordinary flat. No name heuristic, no palette-zero visibility.
;
; Resource lifetime contract:
;   - build must occur while the WAD is open; FlatLoad reads inside the build;
;   - entries own a private FlatImage by value (one 4096-byte pixel copy each),
;     not a borrowed catalog/WAD/image pointer; cache Reset releases every image
;     exactly once and then the entry array; Reset is idempotent;
;   - cache invalidation across WADClose or A->B->A sessions is mandatory: the
;     caller resets and rebuilds; a lookup is only valid for the current build;
;   - no WAD I/O or allocation happens during plane drawing; only the borrowed
;     image pointer is read at draw start and not retained.
;
; Budget: at most the 1,024 visplane cap unique flats; at most 1,024 entries.
; A malformed/truncated flat, closed WAD, missing catalog or exhausted budget fails
; transactionally and leaves the cache empty with a diagnostic.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_PLANEFLATCACHE_PBI, #PB_Constant) = 0

#DOOMPB_PLANEFLATCACHE_PBI = 1

XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "Planes.pbi"
XIncludeFile "PlaneMapping.pbi"

#PLANE_FLAT_CACHE_Magic = $504C4643
#PLANE_FLAT_CACHE_MaxEntries = #PLANE_MaxVisplanes

Structure PlaneFlatEntry
  FlatIndex.l
  RequestedReferences.l
  Loaded.l
  Image.FlatImage
EndStructure

Structure PlaneFlatCache
  Magic.l
  Ready.l
  Count.l
  Capacity.l
  RequestedReferences.l
  UniqueFlats.l
  LoadedFlats.l
  Allocations.l
  *Entries.PlaneFlatEntry
EndStructure

Global gPlaneFlatCache_LastError.s = ""

Procedure PlaneFlatCacheSetError(Message.s)
  gPlaneFlatCache_LastError = Message
EndProcedure

Procedure.s PlaneFlatCacheLastError()
  ProcedureReturn gPlaneFlatCache_LastError
EndProcedure

Procedure.i PlaneFlatCacheIsValid(*Cache.PlaneFlatCache)
  ProcedureReturn Bool(*Cache <> 0 And *Cache\Magic = #PLANE_FLAT_CACHE_Magic And
                        *Cache\Ready <> 0)
EndProcedure

Procedure.i PlaneFlatCacheReset(*Cache.PlaneFlatCache)
  Protected entryIndex.i
  Protected *entry.PlaneFlatEntry

  If *Cache = 0
    PlaneFlatCacheSetError("Plane flat cache pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Cache\Magic = #PLANE_FLAT_CACHE_Magic
    If *Cache\Entries <> 0
      If *Cache\Capacity < 1 Or *Cache\Capacity > #PLANE_FLAT_CACHE_MaxEntries Or
         *Cache\Count < 0 Or *Cache\Count > *Cache\Capacity
        PlaneFlatCacheSetError("Plane flat cache owned pointer/capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      For entryIndex = 0 To *Cache\Count - 1
        *entry = *Cache\Entries + Int(entryIndex) * SizeOf(PlaneFlatEntry)
        If FlatImageReset(@*entry\Image) = #False
          PlaneFlatCacheSetError("Plane flat cache image reset failed: " + FlatLastError())
          ProcedureReturn #False
        EndIf
      Next
      FreeMemory(*Cache\Entries)
    EndIf
  ElseIf *Cache\Magic <> 0
    PlaneFlatCacheSetError("Plane flat cache has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Cache\Entries <> 0
    PlaneFlatCacheSetError("Plane flat cache has an unexplained entry pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Cache, Int(SizeOf(PlaneFlatCache)), 0)
  *Cache\Magic = #PLANE_FLAT_CACHE_Magic
  gPlaneFlatCache_LastError = ""
  ProcedureReturn #True
EndProcedure

; Builds the used-flat cache while WAD is open. *Frame must be Ready and carry the
; exact non-sky marked bands. Each unique FlatPic loads once; duplicate plane
; references increment RequestedReferences and reuse the entry.
Procedure.i PlaneFlatCacheBuild(*Cache.PlaneFlatCache, *Flats.FlatCatalog,
                                *Frame.PlaneFrame)
  Protected *record.PlaneRecord
  Protected planeIndex.l
  Protected used.l = 0
  Protected flatPic.l = 0
  Protected entryIndex.i
  Protected *entry.PlaneFlatEntry
  Protected existing.i
  Protected entriesMemory.i = 0
  Protected uniqueCount.l = 0
  Protected requested.l = 0
  Protected loadedCount.l = 0
  Protected library.i
  Protected failureText.s = ""

  PlaneFlatCacheSetError("")
  If *Cache = 0
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: cache pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Cache\Magic <> 0 And *Cache\Magic <> #PLANE_FLAT_CACHE_Magic
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: cache has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If PlaneFlatCacheReset(*Cache) = #False
    ProcedureReturn #False
  EndIf
  If *Frame = 0 Or PlaneFrameIsValid(*Frame) = #False
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: plane frame is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Flats = 0 Or *Flats\Magic <> #FLAT_CatalogMagic
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If WADIsOpen() = #False
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: no WAD is open; flats must load before WADClose.")
    ProcedureReturn #False
  EndIf
  If *Frame\LastPlane < 0 Or *Frame\LastPlane > #PLANE_FLAT_CACHE_MaxEntries
    PlaneFlatCacheSetError("PlaneFlatCacheBuild: visplane count exceeds the flat cache budget.")
    ProcedureReturn #False
  EndIf

  entriesMemory = AllocateMemory(Int(#PLANE_FLAT_CACHE_MaxEntries) * Int(SizeOf(PlaneFlatEntry)))
  If entriesMemory = 0
    PlaneFlatCacheSetError("Out of memory while allocating the plane flat cache entries.")
    ProcedureReturn #False
  EndIf
  FillMemory(entriesMemory, Int(#PLANE_FLAT_CACHE_MaxEntries) * Int(SizeOf(PlaneFlatEntry)), 0)
  *Cache\Entries = entriesMemory
  *Cache\Capacity = #PLANE_FLAT_CACHE_MaxEntries

  For planeIndex = 0 To *Frame\LastPlane - 1
    *record = *Frame\Records + Int(planeIndex) * SizeOf(PlaneRecord)
    If *record\Sky <> 0
      Continue
    EndIf
    If PlaneRecordHasBands(*Frame, planeIndex, @used) = #False
      failureText = "PlaneFlatCacheBuild: used-band scan failed: " + PlanesLastError()
      Goto PlaneFlatCacheFailure
    EndIf
    If used = 0
      Continue
    EndIf
    flatPic = *record\FlatPic
    If flatPic < 0 Or flatPic >= #FLAT_MaxCount
      failureText = "PlaneFlatCacheBuild: visplane flat index is invalid: " + Str(flatPic) + "."
      Goto PlaneFlatCacheFailure
    EndIf
    requested + 1

    existing = 0
    For entryIndex = 0 To uniqueCount - 1
      *entry = *Cache\Entries + Int(entryIndex) * SizeOf(PlaneFlatEntry)
      If *entry\FlatIndex = flatPic
        *entry\RequestedReferences + 1
        existing = 1
        Break
      EndIf
    Next
    If existing <> 0
      Continue
    EndIf

    If uniqueCount >= #PLANE_FLAT_CACHE_MaxEntries
      failureText = "PlaneFlatCacheBuild: unique flat budget is exhausted."
      Goto PlaneFlatCacheFailure
    EndIf
    *entry = *Cache\Entries + Int(uniqueCount) * SizeOf(PlaneFlatEntry)
    *entry\FlatIndex = flatPic
    *entry\RequestedReferences = 1
    *entry\Loaded = 0
    uniqueCount + 1
  Next

  ; Publish the entry count before image loads so a mid-load failure Reset
  ; releases every image that FlatLoad already allocated (FlatImageReset is
  ; idempotent for not-yet-loaded zero entries).
  *Cache\Count = uniqueCount

  ; Resource loads happen only after the source plane scan; still while WAD open.
  For entryIndex = 0 To uniqueCount - 1
    *entry = *Cache\Entries + Int(entryIndex) * SizeOf(PlaneFlatEntry)
    If FlatLoad(*Flats, *entry\FlatIndex, @*entry\Image) = #False
      failureText = "PlaneFlatCacheBuild: flat " + Str(*entry\FlatIndex) +
                    " load failed: " + FlatLastError()
      Goto PlaneFlatCacheFailure
    EndIf
    *entry\Loaded = 1
    loadedCount + 1
  Next

  *Cache\Ready = 1
  *Cache\Count = uniqueCount
  *Cache\RequestedReferences = requested
  *Cache\UniqueFlats = uniqueCount
  *Cache\LoadedFlats = loadedCount
  *Cache\Allocations = 1 + loadedCount
  gPlaneFlatCache_LastError = ""
  ProcedureReturn #True

  PlaneFlatCacheFailure:
  If failureText = ""
    failureText = gPlaneFlatCache_LastError
  EndIf
  PlaneFlatCacheReset(*Cache)
  PlaneFlatCacheSetError(failureText)
  ProcedureReturn #False
EndProcedure

; Borrowed read-only image address for a resolved flat index, returned exactly as
; the accepted M3-06 WallTextureCacheImagePtr returns its composed-image address.
; Only a successfully built cache can answer; it retains ownership and the
; orchestrator releases it after the frame. No WAD/catalog pointer is stored.
; 0 means failure with a contextual diagnostic; the caller must not retain it.
Procedure.i PlaneFlatCacheImagePtr(*Cache.PlaneFlatCache, FlatIndex.l)
  Protected entryIndex.i
  Protected *entry.PlaneFlatEntry

  PlaneFlatCacheSetError("")
  If PlaneFlatCacheIsValid(*Cache) = #False
    PlaneFlatCacheSetError("Plane flat cache is not initialized.")
    ProcedureReturn 0
  EndIf
  If *Cache\Entries = 0 Or *Cache\Count < 0 Or *Cache\Count > *Cache\Capacity
    PlaneFlatCacheSetError("Plane flat cache owned storage/metadata is inconsistent.")
    ProcedureReturn 0
  EndIf
  If FlatIndex < 0 Or FlatIndex >= #FLAT_MaxCount
    PlaneFlatCacheSetError("Plane flat cache lookup flat index is invalid: " + Str(FlatIndex) + ".")
    ProcedureReturn 0
  EndIf
  For entryIndex = 0 To *Cache\Count - 1
    *entry = *Cache\Entries + Int(entryIndex) * SizeOf(PlaneFlatEntry)
    If *entry\FlatIndex = FlatIndex And *entry\Loaded <> 0
      If *entry\Image\Magic <> #FLAT_ImageMagic Or *entry\Image\Pixels = 0 Or
         *entry\Image\Width <> #FLAT_Width Or *entry\Image\Height <> #FLAT_Height Or
         *entry\Image\PixelCount <> #FLAT_ByteSize
        PlaneFlatCacheSetError("Plane flat cache entry image metadata is invalid.")
        ProcedureReturn 0
      EndIf
      gPlaneFlatCache_LastError = ""
      ProcedureReturn @*entry\Image
    EndIf
  Next
  PlaneFlatCacheSetError("Plane flat cache has no loaded flat for resolved index " + Str(FlatIndex) + ".")
  ProcedureReturn 0
EndProcedure

Procedure.i PlaneFlatCacheGetStats(*Cache.PlaneFlatCache,
                                   *Count.Long, *Capacity.Long,
                                   *RequestedReferences.Long,
                                   *UniqueFlats.Long, *LoadedFlats.Long,
                                   *Allocations.Long)
  If PlaneFlatCacheIsValid(*Cache) = #False
    PlaneFlatCacheSetError("Plane flat cache statistics: cache is not initialized.")
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
  If *UniqueFlats <> 0
    PokeL(*UniqueFlats, *Cache\UniqueFlats)
  EndIf
  If *LoadedFlats <> 0
    PokeL(*LoadedFlats, *Cache\LoadedFlats)
  EndIf
  If *Allocations <> 0
    PokeL(*Allocations, *Cache\Allocations)
  EndIf
  gPlaneFlatCache_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
