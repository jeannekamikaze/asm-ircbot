; This program is free software. It comes without any warranty, to
; the extent permitted by applicable law. You can redistribute it
; and/or modify it under the terms of the Do What The Fuck You Want
; To Public License, Version 2, as published by Sam Hocevar. See
; COPYING for more details.
;
;---------
;INTRODUCTION
;---------
;IRCBOT for Linux x86

;---------
;COMMENTS
;---------
;General information to recall:
;esi holds the socket descriptor
;edi points to the string received from the server (on stack)
;To call send, first push the length of the string to send,
;then a pointer to the string, and afterwards issue call.

BITS 32

;---------
;DATA
;---------

;change data below as appropriate
section .data
	logincmd     db ': NICK asmbot',0xd,0xa,'USER asmbot asmbot irc.freenode.net :asmbot',0xd,0xa
	quit         db 'QUIT :Did you hear that?',0xd,0xa
	joinchannels db 'JOIN #botground',0xd,0xa
	msg_priv     db 'PRIVMSG '
	msg_quit     db 'quit'

section .text
	global _start

;---------
;CODE
;---------
;Alright, code goes here.
;Basically, it is divided into three main parts:
;    Initialisation ->  setting up, connecting to the server, making space for buffer.
;    Main loop      ->  receiving and parsing commands.
;    Ending         ->  send quit message, disconnect from server, and exit.


_start:
	xor eax, eax
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx

	;Make space for variables.
	sub esp, 4
	mov ebp, esp

	;[ebp]    int: 1 when channels have been joined, 0 otherwise.
	;[ebp+4]  int: holds the number of bytes received by recv().

	;Initialise variables.
	mov dword [ebp], 0

socket:
	push edx
	push 0x1
	push 0x2
	mov ecx, esp
	inc bl
	mov al, 102
	int 0x80
	mov esi, eax
	cmp eax, 0
	jb near socket_fail

connect:
	push edx
	push dword 0x4bb8b2c3
	push dword 0x0B1A0002
	mov ecx, esp
	push 0x10
	push ecx
	push esi
	mov ecx, esp
	mov bl, 3
	mov al, 102
	int 0x80
	test eax, eax
	jnz near connect_fail

prepare_buffer:
	;We will need a buffer later on
	;to receive messages from the server.
	push edx
	sub esp, 127+28
	mov edi, esp

login:
	;Send the login information to the server.
	push dword 0    ;Flags
	push dword 67   ;Length
	push logincmd   ;String
	push esi
	call send

recv:
	push dword 0    ;Flags
	push dword 128  ;Len
	push edi        ;buf
	push esi        ;socket
	mov ecx, esp
	mov ebx, 10
	mov eax, 102
	int 0x80
	mov [ebp+4], eax
	test eax, eax
	jz near connection_closed
	jbe near recv_fail
	pop ecx
	pop ecx
	pop ecx
	pop ecx

check_for_ping:
	;String long enough to
	;deal with parsing?
	cmp dword [ebp+4], 6
	jbe recv

	mov edx, edi
	mov ecx, 124

	check_ping_repeat:
	cmp dword [edx], 0x474E4950 ;GNIP
	je pong

	inc edx
	dec ecx
	jnz check_ping_repeat

	jmp check_channels

pong:
	;Now we need to substitute the I
	;in PING for O, so that is reads
	;PONG, and reply to the server with
	;our new string. O = 0x47.
	mov byte [edx+1], 0x4F

	;Send the reply
	push 16
	push edx
	call send

check_channels:
	;Have channels already been joined?
	;If so, jump straight into the message parsing block.
	mov eax, [ebp]
	test eax, eax
	jnz check_message

join_channels:
	;Prudential wait time.
	mov eax, 162
	push dword 0
	push dword 1
	mov ebx, esp
	xor ecx, ecx
	int 0x80

	;Once the server has welcomed us, we can join channels.
	push dword 0 ;Flags
	push dword 17
	push joinchannels
	push esi
	call send

	mov dword [ebp], 1 ;Channels have been joined.

check_message:

	;user@host PRIVMSG #botground :asmbot, quit

	;String long enough to
	;deal with parsing?
	mov ecx, [ebp+4]
	cmp ecx, 9
	jb recv

	mov edx, edi

	check_message_next:
	;PRIVMSG ?
	cmp dword [edx], 0x56495250 ;VIRP
	jne check_message_iterate

	cmp dword [edx+4], 0x2047534D ; GSM
	je check_message_continue

	check_message_iterate:
	inc edx
	dec ecx
	jz recv
	jmp check_message_next

	check_message_continue:

	;Now find the : in the message.
	add edx, 8

	recheck_msg:
	cmp byte [edx], 0x3A
	je parse_command
	inc edx
	dec ecx
	jz recv
	jmp recheck_msg

parse_command:

	;PRIVMSG #Botground :asmbot, quit

	;Is edx pointing near the end of the buffer?
	;If so, there is no need to parse the string.
	cmp ecx, 10
	jb recv

	;Get past the :
	inc edx

	;Now read whatever was said after
	;the : and check for commands.

	;Was our name said ? asmbot, (space)
	cmp dword [edx], 0x626D7361 ;bmsa
	cmp dword [edx+4], 0x202C746F ; ,to
	jne recv

	;Get past the name
	add edx, 8

	;Was quit said?
	push 4
	push msg_quit
	push edx
	call compare
	test eax, eax
	je bye_bye

	jmp recv

	;cmp dword [edx], 0x74697571 ;tiuq
	;jne recv

bye_bye:
	;We say good bye!
	push dword 0	;Flags
	push dword 26
	push quit
	push esi
	call send

shutdown:
	;Close the socket.
	;SHUT_RDWR = 0x2
	push 0x2
	push esi
	mov ecx, esp
	mov ebx, 0xD
	mov eax, 102
	int 0x80
	test eax, eax
	jnz near shutdown_fail

	;Set ebx to 0 for a clean exit call.
	xor ebx, ebx

exit:
	mov eax, 1
	int 0x80

send:
	mov ecx, esp
	add ecx, 4
	mov ebx, 9
	mov eax, 102
	int 0x80
	cmp eax, 0
	jb near send_fail
	pop eax	;ret
	pop ecx	;socket
	pop ecx	;buf
	pop ecx	;len
	pop ecx	;flags
	push eax
	ret

compare:
	pop eax	;ret
	pop edx	; ptr one
	pop ebx	; ptr two
	pop ecx	; Length
	push eax

	compare_loop:
	mov al, [edx]
	xor al, [ebx]
	test al, al
	jnz compare_return

	dec ecx
	test ecx, ecx
	jz compare_equal

	inc edx
	inc ebx
	jmp compare_loop

	compare_equal:
	xor eax, eax

	compare_return:
	ret

fail:
	pop ecx
	pop edx
	mov ebx, 0x1
	mov eax, 0x4
	int 0x80

	;Set ebx to 1 as an error code.
	mov ebx, 1
	jmp exit

;-----------------
;FAIL "FUNCTIONS"
;-----------------
;The fail functions are all listed here.
;The tags are pretty self explanatory.
;Remember to push the length of the string to print
;before calling fail.

recv_fail:
	push 14
	call fail
	db 'recv() failed',0xa

socket_fail:
	push 16
	call fail
	db 'socket() failed',0xa

connection_closed:
	push 48
	call fail
	db'The server closed the connection.',0xa,'Son of a #@!~',0xa

connect_fail:
	push 17
	call fail
	db 'connect() failed',0xa

send_fail:
	push 14
	call fail
	db 'send() failed',0xa

shutdown_fail:
	push 18
	call fail
	db 'shutdown() failed',0xa
