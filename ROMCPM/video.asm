
;------------------------------------------------------------------------------
;
; Z80 CP/M Video Demonstration
; by Daniel Marks

VIDFR   EQU     $2000

VIDWDTH EQU     64
VIDLN   EQU     246
VBLLN   EQU     16

VIDBYT  EQU     VIDWDTH*VIDLN

SYNCPT  EQU     $1B
SHIFTPT EQU     $20
PS2PT   EQU     $19

STRT    ORG     $100
       
        JP      START

DECFR   DB      0            ; always change DECFR before DECTL in interrupt
DECTL   DB      1            ; these are used to terminate the loop

CURCOL  DW      0            ; current offset for scrolling horizontally in framebuffer
FRAMEST DW      0            ; scratch for saving current framebuffer origin

OLDSTK  DW      0            ; old stack pointer
NEWSTK  DS      64           ; new stack pointer
STOPSTK EQU     $-1
BDOS    EQU     5            ; CP/M BDOS call

MSGSTR  DB      13,10,"START PROGRAM",13,10,0
VIDMSG  DB      13,10,"CLEARED VIDEO",13,10,0

START   LD      HL,0
        ADD     HL,SP
        LD      (OLDSTK),HL     ; Save stack ptr
        LD      HL,STOPSTK      ; Use new stack
        LD      SP,HL
        LD      HL,MSGSTR
        CALL    OUTSTR          ; Display message
        CALL    INITVID         ; Initialize frame buffer
        LD      HL,VIDMSG       ; Say we initialized frame buffer
        CALL    OUTSTR
               
NL      LD      A,1             ; Set up to display 60 frames
        LD      (DECFR),A
        LD      A,60
        LD      (DECTL),A
        CALL    VIDEOFR         ; Call display function

        LD      A,(CURCOL)      ; Move scroll register to
        INC     A               ; pan display horizontally
        AND     $0f
        LD      (CURCOL),A

        LD      C,6     ; see if there is a key ready
        LD      E,$FF
        CALL    BDOS
        OR      A
        JP      Z,NL    ; if not, keep scrolling

        LD      HL,(OLDSTK)    ; restore the stack
        LD      SP,HL          ; and leave
        RET
 
;  Outputs a string at HL

OUTSTR  PUSH    AF 
        PUSH    BC
        PUSH    DE
OUTL    LD      A,(HL)      ; Load a character
        OR      A           ; if zero quit
        JR      Z,OUTEX    
        LD      E,A         ; otherwise output using BDOS
        LD      C,2
        PUSH    HL
        CALL    BDOS
        POP     HL
        INC     HL          ; go to next character
        JP      OUTL
OUTEX   POP     DE
        POP     BC
        POP     AF
        RET
        
INITVID LD      A,$92           ; Configure port B as input, C as output
        OUT     (SYNCPT),A
        LD      A,$3
        OUT     (SYNCPT),A      ; Force SD card select lines high! 
        LD      A,$1
        OUT     (SYNCPT),A
        LD      BC,VIDFR
        LD      HL,VIDBYT       ; Start at the top of buffer
CLRV    LD      A,C             ; Fill the buffer with a pattern
        ADD     A,B
        LD      (BC),A
        LD      A,$0
        INC     BC
        DEC     HL
        OR      H
        OR      L
        JP      NZ,CLRV         ; Keep going until the end
        RET                
        
; This is the main video output routine.  All of the timings
; here are cycle dependent!  Don't change the instructions
; without knowing how the timing is changing...        
;
; Yes it is a hack, but getting it to have exactly 15.752 kHz
; horizontal scan rate ain't easy..
;
; There are VIDLN regular scan lines, and then VBLLN 
; vertical blanking lines with inverted sync pulses.
; all of the pulses must occur at 15.752 kHz (or as close as we
; can get it) or the display will not lock onto the scan
; lines.
;
VIDEOFR LD      C,SHIFTPT               ; output to shift register
        LD      DE,(CURCOL)             ; calculate the beginning of the frame buffer
        LD      HL,VIDFR-(VIDWDTH-24)   
        ADD     HL,DE                   ; add offset for current shift window
        LD      (FRAMEST),HL            ; start at current frame
        LD      DE,VIDWDTH-24           
        LD      B,VIDLN         ; Load the number of visible scan lines
LINEST  LD      A,14            ; Send a brief sync pulse (about 4.5 us)
        OUT     (SYNCPT),A
        ADD     HL,DE           ; This add is here to lengthen the sync pulse
        LD      A,15            ; This is not an INC because we need 7 t-states
        OUT     (SYNCPT),A
        LD      A,B             ; Save B register
        
        NOP                     ; Delay between sync and scan line information
        NOP
        NOP
        NOP
        OUTI                    ; Stream 24 bytes of data out to the register
        OUTI                    ; (192 pixels)
        OUTI
        OUTI
        
        OUTI
        OUTI
        OUTI 
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        LD      B,A             ; Load B back
        DJNZ    LINEST          ; Keep going until all scan lines done
        LD      B,0             ; Delay so that inverted sync in vertical blanking
        LD      B,0             
        LD      B,0
        
VBLT    LD      B,VBLLN-1       ; Vertical blanking lines
        JP      VBLSCN
VBLALT  LD      A,VBLLN-1       ; Alternate loop path with the same number of t-states
        JP      VBLSCN
VBLSCN  LD      A,B
        LD      B,28
VWAIT   DJNZ    VWAIT           ; Wait 28 X 13 t-states approx
        NOP                     ; More waiting to line up VBL sync with
        NOP                     ; regular scan line SYNC
        LD      B,A
        LD      A,15            ; Send an inverted sync pulse (4.5 us)
        OUT     (SYNCPT),A      
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14           
        OUT     (SYNCPT),A
        DJNZ    VBLALT

        LD      A,(DECFR)       ; See if we have displayed the number of frames
        LD      B,A
        LD      A,(DECTL)       
        SUB     B
        RET     Z               ; If frames decrement to zero, leave loop
        LD      (DECTL),A
        LD      B,23            ; This is just waiting
        NOP
        NOP 
        LD      B,23            ; We wait for 23 X 13 t-states
VWAIT2  DJNZ    VWAIT2          ; to get the last sync pulse to line up
        LD      HL,(FRAMEST)
        LD      B,VIDLN

        LD      A,15            ; Send a the last sync pulse in frame (4.5 us)
        OUT     (SYNCPT),A
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14     
        OUT     (SYNCPT),A        
        JP      LINEST         ; Send another frame!

