; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Wall-texture compositor.
;
; A texture is composed from its resolved patch placements in definition order.
; Each placement's signed originx/originy positions the top-left corner of the
; source patch inside the texture. Source pixels with mask=1 overwrite earlier
; pixels; transparent source pixels leave the destination untouched. Negative
; origins and placements extending past any edge are clipped safely.
;
; PatchImage.LeftOffset/TopOffset describe internal patch alignment and are NOT
; applied again: a texture placement already carries its own maptexture origin.
;
; Output is an owned row-major 8-bit palette-index plane plus a separate opacity
; mask (0 = uncovered, 1 = covered). Uncovered pixels are index 0. Palette index
; 255 is an ordinary opaque index. No COLORMAP, RGB, alpha or scaling work is
; performed here.
;
; Ownership:
;   - TextureImage is caller-owned and zero-initialized once.
;   - TextureCompose owns private pixel/mask planes and replaces previous data.
;   - TextureImageReset frees both planes, is idempotent, and is safe after a
;     failure. A failed compose leaves the output empty.
;   - Temporary WAD buffers and decoded PatchImage objects are released on
;     every path. The output never borrows them.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_TEXTURE_PBI, #PB_Constant) = 0

#DOOMPB_TEXTURE_PBI = 1

XIncludeFile "Patch.pbi"
XIncludeFile "TextureDefs.pbi"

#TEXTURE_MaxOutputPixels = 16777216

#TEXTURE_ImageMagic      = $54584931

Structure TextureImage
  Magic.l
  Width.l
  Height.l
  PixelCount.q
  OpaqueCount.q
  *Pixels.Byte
  *Mask.Byte
EndStructure

Global gTextureImage_LastError.s = ""

Procedure TextureImageSetError(Message.s)
  gTextureImage_LastError = Message
EndProcedure

Procedure.s TextureLastError()
  ProcedureReturn gTextureImage_LastError
EndProcedure

Procedure.i TextureImageReset(*Image.TextureImage)
  If *Image = 0
    TextureImageSetError("Texture image pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Image\Magic = #TEXTURE_ImageMagic
    If *Image\Pixels <> 0
      FreeMemory(*Image\Pixels)
    EndIf
    If *Image\Mask <> 0
      FreeMemory(*Image\Mask)
    EndIf
  EndIf

  *Image\Magic = 0
  *Image\Width = 0
  *Image\Height = 0
  *Image\PixelCount = 0
  *Image\OpaqueCount = 0
  *Image\Pixels = 0
  *Image\Mask = 0
  gTextureImage_LastError = ""
  ProcedureReturn #True
EndProcedure

; Central failure path. Requires local variables pixels, mask, raw and patch.
Macro TextureComposeAbort(MessageText)
  If raw <> 0
    FreeMemory(raw)
    raw = 0
  EndIf
  PatchReset(@patch)
  If pixels <> 0
    FreeMemory(pixels)
    pixels = 0
  EndIf
  If mask <> 0
    FreeMemory(mask)
    mask = 0
  EndIf
  TextureImageSetError(MessageText)
  ProcedureReturn #False
EndMacro

; Composes catalog texture TextureIndex into *Output. The catalog must be
; resolved against the currently open WAD.
Procedure.i TextureCompose(*Catalog.TextureCatalog, TextureIndex.i, *Output.TextureImage)
  Protected width.l
  Protected height.l
  Protected patchCount.l
  Protected pixelCount.q
  Protected patchIndex.i
  Protected resolvedLump.i
  Protected lumpSize.q
  Protected raw.i = 0
  Protected patch.PatchImage
  Protected originX.l
  Protected originY.l
  Protected pixels.i = 0
  Protected mask.i = 0
  Protected patchX.i
  Protected patchY.i
  Protected destX.q
  Protected destY.q
  Protected sourceOffset.q
  Protected destOffset.q
  Protected opaque.q

  If *Output = 0
    TextureImageSetError("Texture output pointer is null.")
    ProcedureReturn #False
  EndIf
  TextureImageReset(*Output)

  If *Catalog = 0 Or *Catalog\Magic <> #TEXTURE_CatalogMagic
    TextureImageSetError("Texture catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If TextureIndex < 0 Or TextureIndex >= *Catalog\Set1\Count + *Catalog\Set2\Count
    TextureImageSetError("Texture index out of range: " + Str(TextureIndex) + ".")
    ProcedureReturn #False
  EndIf
  If WADIsOpen() = #False
    TextureImageSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  If TextureCatalogGetProperties(*Catalog, TextureIndex, @width, @height, 0, 0, @patchCount, 0) = #False
    TextureImageSetError("Cannot read texture properties: " + TextureDefsLastError())
    ProcedureReturn #False
  EndIf
  If width <= 0 Or height <= 0
    TextureImageSetError("Texture dimensions are invalid.")
    ProcedureReturn #False
  EndIf

  pixelCount = Int(width) * Int(height)
  If pixelCount <= 0 Or pixelCount > #TEXTURE_MaxOutputPixels
    TextureImageSetError("Texture pixel budget exceeded: " + Str(pixelCount) + " (limit " + Str(#TEXTURE_MaxOutputPixels) + ").")
    ProcedureReturn #False
  EndIf

  pixels = AllocateMemory(pixelCount)
  mask = AllocateMemory(pixelCount)
  If pixels = 0 Or mask = 0
    TextureComposeAbort("Out of memory while allocating texture planes.")
  EndIf
  FillMemory(pixels, pixelCount, 0)
  FillMemory(mask, pixelCount, 0)

  For patchIndex = 0 To patchCount - 1
    resolvedLump = TextureCatalogGetResolvedPatchLump(*Catalog, TextureIndex, patchIndex)
    If resolvedLump < 0
      TextureComposeAbort("Texture " + Str(TextureIndex) + " patch " + Str(patchIndex) + " is unresolved.")
    EndIf
    lumpSize = WADLumpSize(resolvedLump)
    If lumpSize <= 0
      TextureComposeAbort("Texture " + Str(TextureIndex) + " patch " + Str(patchIndex) + " has a zero-length WAD lump.")
    EndIf

    raw = AllocateMemory(lumpSize)
    If raw = 0
      TextureComposeAbort("Out of memory while reading texture patch " + Str(patchIndex) + ".")
    EndIf
    If WADReadLump(resolvedLump, raw, lumpSize) = #False
      TextureComposeAbort("Cannot read texture patch " + Str(patchIndex) + ": " + WADLastError())
    EndIf
    If PatchDecode(raw, lumpSize, @patch) = #False
      FreeMemory(raw)
      raw = 0
      TextureComposeAbort("Cannot decode texture patch " + Str(patchIndex) + ": " + PatchLastError())
    EndIf
    FreeMemory(raw)
    raw = 0

    If TextureCatalogGetPatch(*Catalog, TextureIndex, patchIndex, @originX, @originY, 0, 0, 0) = #False
      TextureComposeAbort("Cannot read texture patch placement " + Str(patchIndex) + ": " + TextureDefsLastError())
    EndIf

    For patchY = 0 To patch\Height - 1
      destY = Int(originY) + Int(patchY)
      If destY >= 0 And destY < height
        sourceOffset = Int(patchY) * Int(patch\Width)
        destOffset = destY * Int(width)
        For patchX = 0 To patch\Width - 1
          destX = Int(originX) + Int(patchX)
          If destX >= 0 And destX < width
            If PeekA(patch\Mask + sourceOffset + patchX) = 1
              PokeA(pixels + destOffset + destX, PeekA(patch\Pixels + sourceOffset + patchX))
              PokeA(mask + destOffset + destX, 1)
            EndIf
          EndIf
        Next
      EndIf
    Next

    PatchReset(@patch)
  Next

  For patchIndex = 0 To pixelCount - 1
    If PeekA(mask + patchIndex) = 1
      opaque + 1
    EndIf
  Next

  *Output\Magic = #TEXTURE_ImageMagic
  *Output\Width = width
  *Output\Height = height
  *Output\PixelCount = pixelCount
  *Output\OpaqueCount = opaque
  *Output\Pixels = pixels
  *Output\Mask = mask
  gTextureImage_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i TextureImageGetPixel(*Image.TextureImage, X.i, Y.i)
  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic
    TextureImageSetError("Texture image is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *Image\Width Or Y >= *Image\Height
    TextureImageSetError("Texture coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Image\Pixels + Int(Y) * Int(*Image\Width) + Int(X))
EndProcedure

Procedure.i TextureImageIsOpaque(*Image.TextureImage, X.i, Y.i)
  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic
    TextureImageSetError("Texture image is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= *Image\Width Or Y >= *Image\Height
    TextureImageSetError("Texture coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Image\Mask + Int(Y) * Int(*Image\Width) + Int(X))
EndProcedure

Procedure.q TextureImageOpaqueCount(*Image.TextureImage)
  If *Image = 0 Or *Image\Magic <> #TEXTURE_ImageMagic
    TextureImageSetError("Texture image is not initialized.")
    ProcedureReturn -1
  EndIf
  ProcedureReturn *Image\OpaqueCount
EndProcedure

CompilerEndIf
