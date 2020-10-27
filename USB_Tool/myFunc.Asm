include	USB_Tool.Inc

;预先声明自定义函数原型
WinMain proto :DWORD,:DWORD,:DWORD,:DWORD
_GetVolumeName proto :DWORD
_SetRegKey proto :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
_EditStrCat proto C :DWORD,:DWORD,:DWORD,:VARARG
_CountStrI proto :DWORD,:DWORD
_SHFileOperation proto :DWORD,:DWORD,:DWORD,:DWORD

;代码段定义
.code

;将目标盘符转换成字母形式（转换DEV_BROADCAST_VOLUME.dbcv_unitmask）
_GetVolumeName proc uses esi edi,dwFlag
	mov ecx,26
	mov ebx,dwFlag
@@:
	test ebx,1
	jnz @F
	shr ebx,1
	loop	@B
@@:
	mov eax,5Bh
	sub eax,ecx
	ret
_GetVolumeName endp

;设置注册表指定键值；无返回值
_SetRegKey  proc RootKey,lpszKeyName,lpszValueName,lpszValue,dwValueLength,dwValueType
	LOCAL @pKey

	pushad
	;RegCreateKeyEx指定注册表键不存在则创建，存在则直接打开，键名不区分大小写
	invoke RegCreateKeyEx,RootKey,lpszKeyName,NULL,NULL,REG_OPTION_NON_VOLATILE,KEY_ALL_ACCESS,NULL,addr @pKey,NULL
	.if eax == ERROR_SUCCESS
		invoke RegSetValueEx,@pKey,lpszValueName,NULL,dwValueType,lpszValue,dwValueLength
		invoke RegCloseKey,@pKey
	.endif

	popad
	ret

_SetRegKey endp

;往指定编辑框追加文本，并自动滚动
;注意使用VARARG定义可变参数，函数必须以C调用约定声明
;一旦声明函数体内保存关键寄存器值不能使用pushad/popad，而必须使用uses关键字
;调用方法（无返回值）：invoke	_EditStrCat,hWnd,ID_EDIT,T("!> 单独填充文字...")
;invoke _EditStrCat,hWnd,ID_EDIT,T("!> 第%d个格式化文字%s ..."),3,addr @szPath
_EditStrCat proc C uses edi esi,hWnd,id_Edit,lpszNewFmt,lpszNew:VARARG
	LOCAL	@szBuf[MAX_PATH]:BYTE
	LOCAL	@dwArgs

	invoke	GetDlgItemText,hWnd,id_Edit,addr szMaxBuf,sizeof szMaxBuf
	invoke	lstrlen,addr szMaxBuf
	.if	eax > 32000
		invoke	SetDlgItemText,hWnd,id_Edit,T(0)
	.endif

	invoke	_CountStrI,lpszNewFmt,T("%")
	mov	@dwArgs,eax

	.if	@dwArgs > 0
		;注意可变参数的调用方法
		;注意VARARG要求函数必须符合C调用约定，而直接PUSH可变参数进来顺序会反转，不符合C调用约定
		mov	eax,TYPE DWORD
		mul	@dwArgs
		.WHILE	@dwArgs>0
			sub	eax,TYPE DWORD
			push	lpszNew[eax]
			dec	@dwArgs
		.ENDW
	.endif
	push	lpszNewFmt
	lea	eax,@szBuf
	push	eax
	call	wsprintf
	
	;在追加的信息后添加换行符
	invoke	lstrcat,addr @szBuf,T(0dh,0ah)
	invoke	lstrcat,addr szMaxBuf,addr @szBuf

	invoke	SetDlgItemText,hWnd,id_Edit,addr szMaxBuf

	invoke	GetDlgItem,hWnd,id_Edit
	invoke	SendMessage,eax,WM_VSCROLL,SB_BOTTOM,0

	ret
_EditStrCat endp

;计算源字符串中子串出现的次数（不区分大小写）
_CountStrI	proc	uses esi edi,lpszSource,lpszSub
	LOCAL	@szBuf[10000]:BYTE
	LOCAL	@dwLenSubstr

	invoke	lstrlen,lpszSub
	mov	@dwLenSubstr,eax
	invoke	StrStrI,lpszSource,lpszSub
	xor	ebx,ebx
	.while	eax
		inc	ebx
		add	eax,@dwLenSubstr
		invoke	lstrcpy,addr @szBuf,eax
		invoke	StrStrI,addr @szBuf,lpszSub
	.endw

	mov	eax,ebx
	ret
_CountStrI endp


;批量操作（复制、移动、删除等）指定类型文件（支持通配符）到指定目录
;invoke	_SHFileOperation,FO_MOVE,T("H:\"),T("%s*.lnk|%s*.inf|%s*.ini|%s*.db|%s*.001|%s*.vbs|%s*.vbe"),T("C:\Viruses")

_SHFileOperation	proc	uses esi edi,wFunc,lpszRootPath,lpszFmt,lpszTo
	LOCAL	@pFromBuf[MAX_PATH]:BYTE,@pToBuf[MAX_PATH]:BYTE
	LOCAL	@dwArgs,@struShf:SHFILEOPSTRUCT

	;将可变参数push压栈，调用wsprintf
	invoke	_CountStrI,lpszFmt,T("%s")
	mov	@dwArgs,eax

	mov	eax,lpszRootPath
	.WHILE	@dwArgs>0
		push	eax
		dec	@dwArgs
	.ENDW
	push	lpszFmt
	lea	eax,@pFromBuf
	push	eax
	call	wsprintf

	;替换@pFromBuf中的“|”为NULL——生成SHFILEOPSTRUCT的pFrom样式字符串
	;注意SHFILEOPSTRUCT结构体中pFrom和pTo结尾都必须有两个NULL字节
	invoke	lstrlen,addr @pFromBuf
	mov	@pFromBuf[eax+1],0
	.while	eax > 0
		.while	@pFromBuf[eax]!='|' && eax >0
			dec	eax
		.endw

		.if	eax >0
			mov	@pFromBuf[eax],0
		.endif
	.endw
	
	invoke	lstrcpy,addr @pToBuf,lpszTo
	invoke	lstrlen,addr @pToBuf
	mov	@pToBuf[eax+1],0
	
	invoke	RtlZeroMemory,addr @struShf,sizeof @struShf
	push	wFunc
	pop	@struShf.wFunc
	lea	eax,@pFromBuf
	mov	@struShf.pFrom,eax
	lea	eax,@pToBuf
	mov	@struShf.pTo,eax
	mov	@struShf.fFlags,FOF_NOCONFIRMMKDIR OR FOF_ALLOWUNDO OR FOF_NOCONFIRMATION
	invoke	SHFileOperation,addr @struShf

	ret
_SHFileOperation endp
