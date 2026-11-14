; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Presentation adapter: uploads a finished indexed framebuffer to a PureBasic
; window. This is the only module that knows about windows or image objects;
; FrameBuffer.pbi, Palette.pbi and Patch.pbi stay platform-independent.
;
; Initial mode: native source at 3x nearest-neighbour into a 960 x 600 client
; area. That is square-pixel 8:5, not the historical CRT 4:3 stretch.
;
; The RGBA upload respects DrawingBufferPitch(), the reported pixel format and
; #PB_PixelFormat_ReversedY. Unsupported formats fall back to a Plot() upload.
; The image is built once per displayed frame; the event loop does not re-upload
; an unchanged picture.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_VIDEO_PBI, #PB_Constant) = 0

#DOOMPB_VIDEO_PBI = 1

XIncludeFile "FrameBuffer.pbi"

#VIDEO_DefaultScale = 3
#VIDEO_WindowTitle  = "DoomPB - TITLEPIC (M1-04)"

Global gVideo_LastError.s = ""

Procedure VideoSetError(Message.s)
  gVideo_LastError = Message
EndProcedure

Procedure.s VideoLastError()
  ProcedureReturn gVideo_LastError
EndProcedure

; Uploads canonical RGBA bytes into an already created 24/32-bit PB image.
; Public so it can be exercised by a headless image test if needed.
Procedure.i VideoUploadRGBA(*RGBA.Byte, Width.i, Height.i, Image.i)
  Protected pitch.i
  Protected format.i
  Protected baseFormat.i
  Protected reversed.i
  Protected bytesPerPixel.i
  Protected *buffer.Byte
  Protected *source.Byte
  Protected *target.Byte
  Protected X.i
  Protected Y.i
  Protected targetY.i
  Protected red.i
  Protected green.i
  Protected blue.i
  Protected supported.i = #False

  If *RGBA = 0 Or Width <= 0 Or Height <= 0 Or Image = 0
    VideoSetError("Invalid RGBA upload arguments.")
    ProcedureReturn #False
  EndIf

  If StartDrawing(ImageOutput(Image)) = 0
    VideoSetError("Cannot start drawing on the presentation image.")
    ProcedureReturn #False
  EndIf

  pitch = DrawingBufferPitch()
  format = DrawingBufferPixelFormat()
  *buffer = DrawingBuffer()
  baseFormat = format & ~#PB_PixelFormat_ReversedY
  reversed = Bool((format & #PB_PixelFormat_ReversedY) <> 0)

  Select baseFormat
    Case #PB_PixelFormat_32Bits_RGB, #PB_PixelFormat_32Bits_BGR
      bytesPerPixel = 4
      supported = #True
    Case #PB_PixelFormat_24Bits_RGB, #PB_PixelFormat_24Bits_BGR
      bytesPerPixel = 3
      supported = #True
  EndSelect

  If supported
    If *buffer = 0 Or pitch < Width * bytesPerPixel
      StopDrawing()
      VideoSetError("Unexpected drawing buffer layout (pitch " + Str(pitch) + ").")
      ProcedureReturn #False
    EndIf

    For Y = 0 To Height - 1
      targetY = Y
      If reversed
        targetY = Height - 1 - Y
      EndIf
      *target = *buffer + targetY * pitch
      For X = 0 To Width - 1
        *source = *RGBA + (Y * Width + X) * 4
        red = PeekA(*source)
        green = PeekA(*source + 1)
        blue = PeekA(*source + 2)
        Select baseFormat
          Case #PB_PixelFormat_32Bits_RGB
            PokeA(*target + X * 4, red)
            PokeA(*target + X * 4 + 1, green)
            PokeA(*target + X * 4 + 2, blue)
            PokeA(*target + X * 4 + 3, $FF)
          Case #PB_PixelFormat_32Bits_BGR
            PokeA(*target + X * 4, blue)
            PokeA(*target + X * 4 + 1, green)
            PokeA(*target + X * 4 + 2, red)
            PokeA(*target + X * 4 + 3, $FF)
          Case #PB_PixelFormat_24Bits_RGB
            PokeA(*target + X * 3, red)
            PokeA(*target + X * 3 + 1, green)
            PokeA(*target + X * 3 + 2, blue)
          Case #PB_PixelFormat_24Bits_BGR
            PokeA(*target + X * 3, blue)
            PokeA(*target + X * 3 + 1, green)
            PokeA(*target + X * 3 + 2, red)
        EndSelect
      Next
    Next
  Else
    ; Portable fallback for unusual pixel formats. This runs only once per
    ; presented frame, never inside the idle event loop.
    For Y = 0 To Height - 1
      For X = 0 To Width - 1
        *source = *RGBA + (Y * Width + X) * 4
        Plot(X, Y, RGB(PeekA(*source), PeekA(*source + 1), PeekA(*source + 2)))
      Next
    Next
  EndIf

  StopDrawing()
  gVideo_LastError = ""
  ProcedureReturn #True
EndProcedure

; Shows the framebuffer in a centered window and blocks until the user closes
; it. All window/image/RGBA resources are released on every path.
Procedure.i VideoShowFramebuffer(*FrameBuffer.FrameBuffer, *Palette.PaletteSet, Scale.i = #VIDEO_DefaultScale)
  Protected outputWidth.q
  Protected outputHeight.q
  Protected rgbaBytes.q
  Protected rgba.i = 0
  Protected window.i = 0
  Protected image.i = 0
  Protected gadget.i = 0
  Protected event.i

  If *FrameBuffer = 0 Or *FrameBuffer\Magic <> #FRAMEBUFFER_Magic
    VideoSetError("Framebuffer is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Palette = 0 Or *Palette\Magic <> #PALETTE_Magic
    VideoSetError("Palette is not initialized.")
    ProcedureReturn #False
  EndIf
  If Scale <= 0 Or Scale > #FRAMEBUFFER_MaxScale
    VideoSetError("Display scale is out of range: " + Str(Scale) + ".")
    ProcedureReturn #False
  EndIf

  outputWidth = Int(*FrameBuffer\Width) * Int(Scale)
  outputHeight = Int(*FrameBuffer\Height) * Int(Scale)
  If outputWidth <= 0 Or outputHeight <= 0
    VideoSetError("Invalid display dimensions.")
    ProcedureReturn #False
  EndIf

  rgbaBytes = outputWidth * outputHeight * 4
  rgba = AllocateMemory(rgbaBytes)
  If rgba = 0
    VideoSetError("Out of memory for the RGBA presentation buffer.")
    ProcedureReturn #False
  EndIf

  If FrameBufferScaleNearestRGBA(*FrameBuffer, *Palette, 0, Scale, rgba, rgbaBytes) = #False
    VideoSetError("Cannot convert the framebuffer: " + FrameBufferLastError())
    FreeMemory(rgba)
    ProcedureReturn #False
  EndIf

  ; #PB_Window_InnerCoordinate makes the requested size the client area, so the
  ; 3x image is not reduced by the window border.
  window = OpenWindow(#PB_Any, 0, 0, outputWidth, outputHeight, #VIDEO_WindowTitle,
                      #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_InnerCoordinate)
  If window = 0
    VideoSetError("Cannot open the presentation window.")
    FreeMemory(rgba)
    ProcedureReturn #False
  EndIf

  image = CreateImage(#PB_Any, outputWidth, outputHeight, 32)
  If image = 0
    VideoSetError("Cannot create the presentation image.")
    CloseWindow(window)
    FreeMemory(rgba)
    ProcedureReturn #False
  EndIf

  If VideoUploadRGBA(rgba, outputWidth, outputHeight, image) = #False
    FreeImage(image)
    CloseWindow(window)
    FreeMemory(rgba)
    ProcedureReturn #False
  EndIf

  gadget = ImageGadget(#PB_Any, 0, 0, outputWidth, outputHeight, ImageID(image))
  If gadget = 0
    VideoSetError("Cannot create the image gadget.")
    FreeImage(image)
    CloseWindow(window)
    FreeMemory(rgba)
    ProcedureReturn #False
  EndIf

  Repeat
    event = WaitWindowEvent()
  Until event = #PB_Event_CloseWindow

  CloseWindow(window)
  FreeImage(image)
  FreeMemory(rgba)
  gVideo_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
