;The MIT License
;
;Copyright (c) 2008 Dylan Smith
;
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this software and associated documentation files (the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the Software is
;furnished to do so, subject to the following conditions:
;
;The above copyright notice and this permission notice shall be included in
;all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;THE SOFTWARE.

; DHCP Client
.include	"spectranet.inc"
.include	"sysvars.inc"
.include	"dhcpdefs.inc"
.include	"ctrlchars.inc"
.include	"sockdefs.inc"
.text
;-------------------------------------------------------------------------
; F_dhcp
; Performs all the actions of a DHCP client, displaying helpful messages
; on the console as the process proceeds.
; In summary, this consists of:
;   - Generate DHCPDISCOVER. This generates the XID, initializes the
;     hardware (no IP address) and broadcasts a DHCPDISCOVER message.
;   - Wait for and receive DHCPOFFER. This message is an offer from a
;     server - the first offer to come back is processed (a network
;     can have more than one DHCP server).
;   - In response to the DHCPOFFER, send a DHCPREQUEST. This contains
;     a readback of the information offered by the previous DHCPOFFER.
;   - Wait for and process the DHCPACK. Once a correct DHCPACK is received,
;     the hardware is set up with the data returned.
; The DHCP client requests an IP address, subnet mask and default gateway,
; and any DNS servers.

.globl F_dhcp
F_dhcp:
	ld bc, 0xFFFF		; delay for long enough for hw to init
.delay1:
	push hl			; waste a load of time
	push bc
	push de
	pop de
	pop bc
	pop hl
	dec bc
	ld a, b
	or c
	jr nz, .delay1

	ld hl, STR_dhcpinit
	call PRINT42
	ld hl, STR_dhcpdiscover
	call PRINT42

	ld b, 8			; num of retries
.retrydiscover1:
	push bc

	call F_dhcpdiscover
	jr c, .borked1

	call F_dhcprecvoffer
	jr nc, .offer1
	cp DHCP_INTERRUPTED	; BREAK pressed?
	jr z, .break1
	ld a, '.'
	call PUTCHAR42
	pop bc
	djnz .retrydiscover1

	push af			; ran out of retries
	ld a, NEWLINE		; so put a CR
	call PUTCHAR42
	pop af
	jr .borked1		; then report the error

.break1:	
	pop bc			; fix stack
	jr .borked1

.offer1:
	pop bc			; fix stack
	ld hl, STR_dhcpoffer
	call PRINT42

	ld hl, STR_dhcprequest
	call PRINT42
	call F_dhcpsendrequest
	jr c, .borked1

	call F_dhcprecvack
	jr c, .borked1
	ld hl, STR_dhcpack
	call PRINT42

	; Display the IP address that we got back.
	ld hl, STR_ipaddr
	call PRINT42
	ld hl, v_dhcpreqaddr
	ld de, buf_workspace
	call LONG2IPSTRING
	ld hl, buf_workspace
	call PRINT42
	ld a, NEWLINE
	call PUTCHAR42
	ld hl, v_ethflags	; set "have an IP" bit
	set 0, (hl)
	ret

.borked1:
	push af
	ld hl, STR_failed
	call PRINT42
	pop af
	ld hl, v_workspace
	call ITOA8
	ld hl, v_workspace
	call PRINT42
	ld a, NEWLINE
	call PUTCHAR42

	; pause - TODO: something a bit better (perhaps a keypress?)
	ld bc, 0xFFFF
.bdelay1:
	dec bc
	push hl
	push de
	push bc
	pop bc
	pop de
	pop hl
	ld a, b
	or c
	jr nz, .bdelay1
	
	ret

STR_dhcpinit:	defb "Press BREAK to interrupt.",NEWLINE,0
STR_dhcpdiscover:	defb "DHCPDISCOVER",0
STR_dhcpoffer:		defb NEWLINE,"DHCPOFFER",NEWLINE,0
STR_dhcprequest:		defb "DHCPREQUEST",NEWLINE,0
STR_dhcpack:		defb "DHCPACK",NEWLINE,0
STR_failed:		defb "DHCP failed with return code ",0
STR_ipaddr:		defb "Allocated IP address ",0
STR_interrupted:		defb NEWLINE,"BREAK pressed",NEWLINE,0

;-------------------------------------------------------------------------
; F_dhcpdiscover
; Creates and sends the DHCPDISCOVER message.
.globl F_dhcpdiscover
F_dhcpdiscover:
	; Most of the DHCPDISCOVER message is zeros, so we can
	; save a lot of effort by starting with a workspace set to that.
	ld hl, buf_message
	ld de, buf_message+1
	ld bc, dhcp_msglen
	ld (hl), 0
	ldir

	; Set the standard parts of the header.
	ld hl, buf_message
	ld (hl), dhcp_opval	; dhcp op
	inc l
	ld (hl), dhcp_htypeval	; dhcp htype
	inc l
	ld (hl), dhcp_hlenval	; dhcp htype length

	; Create a session identifier
	call RAND16
	ld (buf_message+dhcp_xid), hl
	ld (v_dhcpxid), hl
	call RAND16
	ld (buf_message+dhcp_xid+2), hl
	ld (v_dhcpxid+2), hl

	; Copy the request options data to the buffer.
	ld hl, DHCPDISCOVER_BLOCK
	ld de, buf_message+dhcp_options
	ld bc, DHCPBLOCKSZ
	ldir

	; Copy the hardware address to the memory pointed by de
	call GETHWADDR

	; Copy the hardware address into the header, too.
	ld de, buf_message+dhcp_chaddr
	call GETHWADDR

	; Re-initialize other hardware registers to zero
	call DECONFIG
.send2:
	; Send the assembled DHCP message.	
	ld c, SOCK_DGRAM	; Datagram (UDP) socket
	call SOCKET
	ret c			; error on carry
	ld (v_dhcpfd), a	; save the socket fd

	; The DHCP request should come from port 68 and go to port 67	
	ld hl, v_dhcpsockinfo	; socket info structure
	ld b, 4
.fill2:
	ld (hl), 0xFF		; dest address = 255.2552.2552.2552
	inc l
	djnz .fill2
	ld hl, 67		; destination port
	ld (v_dhcpsockinfo+4), hl
	inc l
	ld (v_dhcpsockinfo+6), hl

	; send the request
	ld a, (v_dhcpfd)
	ld hl, v_dhcpsockinfo
	ld de, buf_message
	ld bc, dhcp_msglen
	call SENDTO
	jp c, F_closeonerror
	ret

;---------------------------------------------------------------------------
; F_dhcprecvoffer
; Wait for a DHCPOFFER message. The assumption is that F_dhcpdiscover
; was called, and has opened a UDP socket for the DHCP messages.
.globl F_dhcprecvoffer
F_dhcprecvoffer:
	; bind to port 68 for the incoming message
	ld a, (v_dhcpfd)
	ld de, 68		; port 68
	call BIND
	ret c

	call F_waitfordhcpmsg	; poll for message
	ret c

	ld hl, v_dhcpsockinfo
	ld de, buf_message
	ld bc, dhcp_msglen
	ld a, (v_dhcpfd)
	call RECVFROM
	jp c, F_closeonerror	; leave on error

	; Check the XID.
	;call F_comparexid
	;ret c			; bad XID, return now

	; Retrieve the server address from the options block, we need
	; it for the subsequent DHCPREQUEST.
	ld hl, buf_message+dhcp_options+4
	ld de, v_dhcpserver
	ld b, dhcp_opt_server
	call F_dhcpgetoption
	jp c, F_closeonerror	; leave on error

	; Get the lease
	ld hl, buf_message+dhcp_options+4
	ld de, v_dhcplease	
	ld b, dhcp_opt_lease
	call F_dhcpgetoption
	jp c, F_closeonerror	; leave on error

	; Save the YIADDR parameter, this is the IP the server wants
	; to give us, this needs to be sent back in the DHCPREQUEST.
	ld hl, buf_message+dhcp_yiaddr
	ld de, v_dhcpreqaddr
	ldi
	ldi
	ldi
	ldi
	ret

;---------------------------------------------------------------------------
; F_dhcpsendrequest
; Turn around the data sent in the DHCPOFFER message with the right
; bits tweaked to turn it into a DHCPREQUEST.
.globl F_dhcpsendrequest
F_dhcpsendrequest:		
	; Most of the DHCPDISCOVER message is zeros, so we can
	; save a lot of effort by starting with a workspace set to that.
	ld hl, buf_message
	ld de, buf_message+1
	ld bc, dhcp_msglen
	ld (hl), 0
	ldir

	; Set the standard parts of the header.
	ld hl, buf_message
	ld (hl), dhcp_opval	; dhcp op
	inc l
	ld (hl), dhcp_htypeval	; dhcp htype
	inc l
	ld (hl), dhcp_hlenval	; dhcp htype length

	; Copy the XID
	ld hl, v_dhcpxid
	ld de, buf_message+dhcp_xid
	ldi
	ldi
	ldi
	ldi

	; Copy the request options data to the buffer.
	ld hl, DHCPDISCOVER_BLOCK
	ld de, buf_message+dhcp_options
	ld bc, DHCPBLOCKSZ
	ldir
	; modify the message from DISCOVER to REQUEST
	ld hl, buf_message+dhcp_options+6
	ld (hl), dhcp_request

	; Get the hardware address into the buffer at de
	call GETHWADDR

	; Add options for server address and client IP
	ex de, hl			; move pointer back to hl
	ld (hl), dhcp_opt_server	; Server ID
	inc hl
	ld (hl), 4			; 4 bytes
	inc hl
	ld de, v_dhcpserver		; passed to us in the OFFER msg
	ex de, hl
	ldi				; copy it into the DHCPREQUEST
	ldi
	ldi
	ldi
	ex de, hl
	ld (hl), dhcp_opt_reqaddr	; Request the address we were offered
	inc hl
	ld (hl), 4			; which is 4 bytes long
	inc hl
	ld de, v_dhcpreqaddr		; and was passed in the DHCPOFFER
	ex de, hl
	ldi
	ldi
	ldi	
	ldi
	
	; Replace the lease with what we were offered.
	ld hl, v_dhcplease
	ld de, DHCPLEASE_OFFSET
	ldi
	ldi
	ldi
	ldi

	; Copy the hardware address into the header, too.
	ld de, buf_message+dhcp_chaddr
	call GETHWADDR

.send4:
	; The DHCP request should come from port 68 and go to port 67	
	ld hl, v_dhcpsockinfo	; socket info structure
	ld b, 4
.fill4:
	ld (hl), 0xFF		; dest address = 255.2554.2554.2554
	inc l
	djnz .fill4
	ld hl, 67		; destination port
	ld (v_dhcpsockinfo+4), hl
	inc l
	ld (v_dhcpsockinfo+6), hl

	; send the request
	ld a, (v_dhcpfd)
	ld hl, v_dhcpsockinfo
	ld de, buf_message
	ld bc, dhcp_msglen
	call SENDTO
	jp c, F_closeonerror	; leave on error
	ret

;---------------------------------------------------------------------------
; F_dhcprecvack
; Receives the DHCPACK message and extracts the fields that we require.
.globl F_dhcprecvack
F_dhcprecvack:		
	; bind to port 68 for the incoming message
	ld a, (v_dhcpfd)
	ld de, 68		; port 68
	call BIND
	ret c

	; Receive the ACK (or possibly NAK) message
	ld a, (v_dhcpfd)
	ld hl, v_dhcpsockinfo
	ld de, buf_message
	ld bc, dhcp_msglen
	ld a, (v_dhcpfd)
	call RECVFROM
	jp c, F_closeonerror

	ld a, (v_dhcpfd)
	call CLOSE

	; Check the XID.
	call F_comparexid
	ret c			; bad XID, return now

	; Save YIADDR, this should be the same as what was in the
	; DHCPOFFER but we'll take no chances.
	ld hl, buf_message+dhcp_yiaddr
	ld de, v_dhcpreqaddr
	ldi
	ldi
	ldi
	ldi

	; Set the hardware up with the IPv4 address
	ld hl, buf_message+dhcp_yiaddr
	call IFCONFIG_INET

	; Now get our options.
	ld hl, v_nameserver1	; initialize nameserver copy
	ld (v_nspointer), hl
	ld hl, buf_message+dhcp_options+4
	ld b, 0			; BC = length of option
.optloop5:
	ld a, (hl)		; Option
	inc hl
	ld c, (hl)		; Length
	inc hl
	cp dhcp_opt_msg		; Message type? (usually 1st in the list)
	jr z, .checkmsg5
	cp dhcp_opt_gateway	; Gateway address?
	jr z, .copygw5
	cp dhcp_opt_netmask	; Netmask?
	jr z, .copynetmask5
	cp dhcp_opt_dns		; DNS server?
	jr z, .copydns5
	and a			; End of options?
	ret z			; in which case return now
	add hl, bc		; move hl to next option
	jr .optloop5
.copygw5:
	call IFCONFIG_GW	; set the gateway address
	jr .optloop5
.copynetmask5:
	call IFCONFIG_NETMASK	; set the netmask
	jr .optloop5
.copydns5:
	ld de, (v_nspointer)
	ld a, v_nsend % 256	; address of end of nameserver memory
	cp e			; no more space?
	jr z, .skipdns5
	ldir
	ld (v_nspointer), de
	jr .optloop5
.skipdns5:
	ld c, 4
	add hl, bc
	jr .optloop5
.checkmsg5:
	ld a, (hl)		; Get the message type (always 1 byte long)
	cp dhcp_msg_ack		; check that it's a DHCPACK
	inc hl			; message is 1 byte long
	jr z, .optloop5		; if so, continue
	ld a, DHCP_NAK		; if not set error code and exit
	jp F_error

;---------------------------------------------------------------------------
; F_dhcpgetoption
; Gets a single option from the DHCP options field.
; HL = pointer to DHCP options block (after the magic cookie)
; DE = pointer to memory to copy the result
; B = option to search for
.globl F_dhcpgetoption
F_dhcpgetoption:
	ld a, (hl)	; get option
	and a		; zero?
	jr z, .notfound6	; option not found
	inc hl
	ld c, (hl)	; get length of option
	inc hl
	cp b		; is it the option we're looking for?
	ld a, b		; save option in A
	ld b, 0		; bc now = size of option
	jr nz, .nextopt6	; no - go for the next option
	ldir		; copy option to destination buffer
	ret		; done
.nextopt6:
	add hl, bc	; add length to hl to point at the next option
	ld b, a		; get back the option
	jr F_dhcpgetoption
.notfound6:
	ld a, DHCP_OPTNOTFOUND	; return code
	jp F_error

;--------------------------------------------------------------------------
; F_comparexid
; Compares the XID field received in a DHCP message with the XID that
; we sent in the first instance. Carry is set if the compare fails,
; and A is set to the DHCP_BAD_XID return code on failure.
.globl F_comparexid
F_comparexid:
	ld hl, buf_message+dhcp_xid
	ld de, v_dhcpxid
	ld b, 4
.cmploop7:
	ld a, (de)
	cp (hl)
	jr nz, .badxid7
	inc hl
	inc de
	djnz .cmploop7
	ret
.badxid7:
	ld a, DHCP_BAD_XID
	jp F_error

;--------------------------------------------------------------------------
; F_waitfordhcpmsg
; Waits for DHCP data, and returns with carry set if we poll for too long
; and have not got a response. Also allows for user (keyboard) interruption.
.globl F_waitfordhcpmsg
F_waitfordhcpmsg:
	ld bc, dhcp_polltime
.loop8:
	push bc
	ld bc, 0x7ffe		; read B to SPACE
	in a, (c)		; check for BREAK
	cp 0xBE			
	jr z, .interrupted8
	ld a, (v_dhcpfd)
	call POLLFD		; data ready for this file descriptor?
	pop bc
	jp c, F_closeonerror	; an error in pollfd
	ret nz			; data is ready
	dec bc
	ld a, b
	or c			; check bc for zero
	jr nz, .loop8		; make another loop
	ld a, DHCP_TIMEOUT	; error code is timeout
	jr F_closeonerror	; close and return
.interrupted8:
	pop bc			; restore stack
	ld hl, STR_interrupted
	call PRINT42
	ld a, DHCP_INTERRUPTED	; just fall through to closeonerror

;--------------------------------------------------------------------------
; F_closeonerror
; A helper function to close and return with the carry flag set.
.globl F_closeonerror
F_closeonerror:
	push af
	ld a, (v_dhcpfd)
	call CLOSE
	pop af
; F_error
; Set flag bits and return
F_error:
	ld hl, v_ethflags
	res 0, (hl)
	scf
	ret

