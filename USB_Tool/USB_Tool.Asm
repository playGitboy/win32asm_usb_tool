include	myFunc.Asm

;代码段定义
.code

start:
	invoke GetModuleHandle,NULL
	mov    hInstance,eax

	invoke GetCommandLine
	invoke WinMain,hInstance,NULL,eax,SW_SHOWDEFAULT
	invoke ExitProcess,eax

WinMain proc hInst:HINSTANCE,hPrevInst:HINSTANCE,CmdLine:LPSTR,CmdShow:DWORD
	LOCAL @wc:WNDCLASSEX
	LOCAL @msg:MSG
	
	;初始化WNDCLASSEX结构体
	invoke	RtlZeroMemory,addr @wc,sizeof @wc
	mov   @wc.cbSize,SIZEOF WNDCLASSEX
	mov   @wc.style,CS_HREDRAW or CS_VREDRAW
	;设置窗口回调函数WndProc
	mov   @wc.lpfnWndProc,OFFSET WndProc
	push  hInstance
	pop   @wc.hInstance
	mov   @wc.hbrBackground,COLOR_BTNFACE+1
	invoke	GetTickCount
	invoke	wsprintf,addr szClassName,T("%08X"),eax
	mov   @wc.lpszClassName,OFFSET szClassName

	invoke	LoadIcon,NULL,IDI_APPLICATION
	mov	@wc.hIcon,eax
	mov	@wc.hIconSm,eax

	invoke	LoadCursor,NULL,IDC_ARROW
	mov	@wc.hCursor,eax

	invoke	RegisterClassEx,addr @wc
	;样式设置为固定大小
	INVOKE	CreateWindowEx,NULL,ADDR szClassName,T("USB Monitor"),WS_SYSMENU OR WS_OVERLAPPED OR WS_MINIMIZEBOX,\
			CW_USEDEFAULT,CW_USEDEFAULT,500,350,NULL,NULL,hInst,NULL

	;默认不显示主界面，可按快捷键WIN+O显示出来
	;mov   @hwnd,eax
	;invoke ShowWindow,@hwnd,SW_SHOWNORMAL
	;invoke UpdateWindow,@hwnd

	.WHILE TRUE
		invoke GetMessage,ADDR @msg,NULL,0,0
		.BREAK .IF (!eax)
		invoke TranslateMessage,ADDR @msg
		invoke DispatchMessage,ADDR @msg
	.ENDW

	mov     eax,@msg.wParam
	ret
WinMain endp

WndProc proc hWnd:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	@szPath[MAX_PATH]:BYTE,@szVolName[MAX_PATH]:BYTE
	LOCAL	@szVolSn[20]:BYTE,@dwVolSN:DWORD

	LOCAL	@hMutex:HINSTANCE

	LOCAL	@pToBuf[MAX_PATH]:BYTE

	LOCAL	@hAutoInf,@dwAutoInflen,@autoInfCon[2048]:BYTE

	LOCAL	@selfExePath[MAX_PATH]:BYTE

	LOCAL	@hLnk:HANDLE,@dwLnk

	LOCAL	@osVer:OSVERSIONINFOEX


	.IF uMsg==WM_CREATE
		;创建互斥变量防止程序多次运行（注意程序退出时删除）
		invoke	CreateMutex,NULL,FALSE,T("usb_monitor")
		mov 	@hMutex,eax
		invoke	GetLastError
		.if	eax == ERROR_ALREADY_EXISTS
			invoke	SendMessage,hWnd,WM_DESTROY,NULL,NULL
		.endif

		;主窗体中创建多行编辑框
		invoke	CreateWindowEx,WS_EX_TOOLWINDOW,T("Edit"),NULL,ES_AUTOVSCROLL OR WS_CHILD OR WS_VISIBLE OR ES_MULTILINE,0,0,500,350,hWnd,ID_EDIT,hInstance,NULL
		;修改编辑框字体（默认粗体不美观）
		invoke	CreateFont,NULL,NULL,NULL,NULL,FW_NORMAL,FALSE,FALSE,FALSE,GB2312_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,T("Consolas")
		invoke	SendDlgItemMessage,hWnd,ID_EDIT,WM_SETFONT,eax,TRUE

		;注册全局热键（注意程序退出时删除）
		invoke	GlobalAddAtom,addr szShowHotKey
		mov	dwShowWinId,eax
		invoke	RegisterHotKey,hWnd,dwShowWinId,MOD_WIN,"O"
		.if	!eax
			;注意MASM中“<>”符号用于变量定义等具有特殊意义，字符串中要使用该字符需要“!”进行转义
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Failed to register the HotKey %s !"),T("Win+O")
		.else
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Show window : %s !"),T("Win + O")
		.endif

		invoke	GlobalAddAtom,addr szHideHotKey
		mov	dwHideWinId,eax
		invoke	RegisterHotKey,hWnd,dwHideWinId,MOD_WIN,"C"
		.if	!eax
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Failed to register the HotKey %s !"),T("Win+C")
		.else
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Hide window : %s !"),T("Win + C")
		.endif

		invoke	GlobalAddAtom,addr szSuperMode
		mov	dwSuperId,eax
		invoke	RegisterHotKey,hWnd,dwSuperId,MOD_WIN,"S"
		.if	!eax
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Failed to register the HotKey %s !"),T("Win+S")
		.else
			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Super mode : %s !"),T("Win + S")
		.endif

		invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Ready to listen...")

		;将本程序加入开机启动项
		invoke GetModuleFileName,NULL,addr @selfExePath,sizeof @selfExePath
		.if eax
		    invoke _SetRegKey,HKEY_LOCAL_MACHINE,T("Software\Microsoft\Windows\CurrentVersion\Run"),T("USB Tool"),addr @selfExePath,eax,REG_SZ
		.endif


		;显示系统隐藏文件、扩展名
		invoke	_SetRegKey,HKEY_LOCAL_MACHINE,T("SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\Hidden\SHOWALL"),T("CheckedValue"),T(1),4,REG_DWORD
		;注意区别，Hidden值为1是显示隐藏文件，为2才是隐藏文件
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("Hidden"),T(1),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("HideFileExt"),T(0),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("ShowSuperHidden"),T(1),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("SuperHidden"),T(0),4,REG_DWORD
		;免重启应用注册表更新
		invoke	SHChangeNotify,SHCNE_ASSOCCHANGED,SHCNF_IDLIST,NULL,NULL
	.ELSEIF uMsg==WM_DESTROY
		;删除全局热键、释放互斥变量等
		invoke	ReleaseMutex,@hMutex

		invoke	UnregisterHotKey,hWnd,dwShowWinId
		invoke	GlobalDeleteAtom,dwShowWinId

		invoke	UnregisterHotKey,hWnd,dwHideWinId
		invoke	GlobalDeleteAtom,dwHideWinId

		invoke	UnregisterHotKey,hWnd,dwSuperId
		invoke	GlobalDeleteAtom,dwSuperId

		;不显示系统隐藏文件和扩展名
		invoke	_SetRegKey,HKEY_LOCAL_MACHINE,T("SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\Hidden\SHOWALL"),T("CheckedValue"),T(0),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("Hidden"),T(2),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("HideFileExt"),T(1),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("ShowSuperHidden"),T(0),4,REG_DWORD
		invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"),T("SuperHidden"),T(1),4,REG_DWORD
		invoke	SHChangeNotify,SHCNE_ASSOCCHANGED,SHCNF_IDLIST,NULL,NULL
		invoke	PostQuitMessage,NULL
	.ELSEIF	uMsg == WM_DEVICECHANGE
		mov	eax,wParam
		.IF	eax == DBT_DEVICEARRIVAL
			;新设备插入，重新初始化全局变量
			mov	bAutoInf,FALSE
			mov	bBlankNameDir,FALSE
			mov	bLnk,FALSE

			;系统底层设备插入消息，需检测lParam以进一步区分设备类型
			mov	ebx,lParam
			assume	ebx:ptr DEV_BROADCAST_HDR
			.if	[ebx].dbch_devicetype == DBT_DEVTYP_VOLUME
				assume	ebx:ptr DEV_BROADCAST_VOLUME
				;将新插入的可移动设备盘符转换并格式化为“H:\”形式
				invoke	_GetVolumeName,[ebx].dbcv_unitmask
				invoke	wsprintf,addr @szPath,T("%c:\"),eax,0

				;尝试获取可移动设备卷标
				invoke	GetVolumeInformation,addr @szPath,addr @szVolName,sizeof @szVolName,addr @dwVolSN,NULL,NULL,NULL,NULL
				invoke	lstrlen,addr @szVolName
				.if	eax > 0
					invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Found USB device %s ..."),addr @szVolName
				.else
					invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Found USB device %s ..."),addr @szPath
				.endif

				;获取可移动设备总空间和可用空间大小
				invoke	GetDiskFreeSpaceEx,addr @szPath,NULL,addr dwTotalNum,addr dwFreeNum
				.if	eax
					;难点：StrFormatByteSize64第一个参数要求QWORD类型(64位)，相当于连续两个DWORD
					invoke	StrFormatByteSize64,dwTotalNum,dwTotalNum+4,addr szBuf,sizeof szBuf
					invoke	_EditStrCat,hWnd,ID_EDIT,T("!> The volume: %s"),addr szBuf
					invoke	StrFormatByteSize64,dwFreeNum,dwFreeNum+4,addr szBuf,sizeof szBuf
					invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Free space: %s"),addr szBuf
				.endif

				;判断可移动设备根目录是否存在“autorun.inf”文件（不区分大小写）
				invoke	lstrcpy,addr szBuf,addr @szPath
				invoke	lstrcat,addr szBuf,T("autorun.inf")
				;要区分是否为同名目录，不要使用PathFileExists（该API无法区分指定路径是文件/目录）
				invoke	GetFileAttributes,addr szBuf
				.if	eax != INVALID_FILE_ATTRIBUTES && eax != FILE_ATTRIBUTE_DIRECTORY
					;判断autorun.inf文件是否包含运行或添加右键菜单等命令关键字——“open”或“shell”
					;autorun.inf通常包含几个节，恶意程序要想自动运行必在名为“[autorun]”的节中做文章
					invoke	CreateFile,addr szBuf,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL
					mov	@hAutoInf,eax
					.if	eax != INVALID_HANDLE_VALUE
						invoke	RtlZeroMemory,addr @autoInfCon,sizeof @autoInfCon
						invoke	ReadFile,@hAutoInf,addr @autoInfCon,2048,addr @dwAutoInflen,NULL
						.if	eax
							invoke	StrStrI,addr @autoInfCon,T(0Dh,0Ah,"open")
							mov	ebx,eax
							invoke	StrStrI,addr @autoInfCon,T(0Dh,0Ah,"shell")
							.if	eax || ebx
								mov	bAutoInf,TRUE
								invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Found something like AUTORUN virus ...")
							.else
								mov	bAutoInf,FALSE
							.endif
						.endif
					.endif
					invoke	CloseHandle,@hAutoInf
				.endif

				;注意同一空名目录在xp和Win7中短文件名不同，需要根据系统版本自动适应路径
				invoke	lstrcpy,addr szBlankDir,addr @szPath
				invoke	RtlZeroMemory,addr @osVer,sizeof @osVer
				mov	@osVer.dwOSVersionInfoSize,sizeof @osVer
				mov	@osVer.dwMajorVersion,6

				invoke	VerSetConditionMask,0,0,VER_MAJORVERSION,VER_GREATER_EQUAL
				;难点：API返回值类型是QWORD，而x86系统中32位寄存器类型是DWORD，默认eax寄存器存低位，edx存高位
				invoke	VerifyVersionInfo,addr @osVer,VER_MAJORVERSION,eax,edx
				.if	eax
					invoke	lstrcat,addr szBlankDir,T("9DEC~1")
				.else
					invoke	lstrcat,addr szBlankDir,T("0A00~1")
				.endif
				;判断设备根目录是否存在空名目录
				invoke	PathFileExists,addr szBlankDir
				.if	eax
					mov	bBlankNameDir,TRUE
				.else
					mov	bBlankNameDir,FALSE
				.endif

				;判断设备根目录是否存在"REMOVA~1.LNK"文件
				invoke	lstrcpy,addr szBuf,addr @szPath
				invoke	lstrcat,addr szBuf,T("REMOVA~1.LNK")
				invoke	PathFileExists,addr szBuf
				.if	eax
					;获取LNK文件属性"目标"路径值
					invoke	CreateFile,addr szBuf,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL
					.if	eax
						mov	@hLnk,eax
						invoke	GetFileSize,@hLnk,NULL
						lea	ebx,@dwLnk
						invoke	ReadFile,@hLnk,addr szMaxBuf,eax,ebx,NULL
						.if	eax
							;参考LNK文件格式，从其内容中解析出"目标"路径值
							lea	esi,szMaxBuf
							add	esi,4Ch

							xor	eax,eax
							mov	ax,word ptr[esi]
							add	esi,eax
							add	esi,TYPE WORD	;相当于add esi,2h

							push	esi
							add	esi,10h
							mov	eax,dword ptr[esi]
							pop	esi
							add	esi,eax

							;此时esi即为“目标”路径字符串的指针
							invoke	lstrlen,esi
							.if	eax
								invoke	StrStrI,esi,T("rundll32")
								mov	ebx,eax
								invoke	StrStrI,esi,T("wscript")
								.if	eax || ebx
									mov	bLnk,TRUE
								.else
									mov	bLnk,FALSE
								.endif
							.endif
						.endif
						invoke	CloseHandle,@hLnk
					.endif
				.endif

				;如果根目录同时存在符合特征的LNK文件和空名目录，则确认该设备中了LNK病毒
				.if	bBlankNameDir && bLnk
					invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Found something like LNK virus ...")

					;“ntsd -c q -pn *.exe”功能更强，但vista+不支持
					invoke	WinExec,T("cmd /c taskkill /F /IM rundll32.exe /IM wuauclt.exe /IM TrustedInstaller.exe /T && assoc .lnk=lnkfile"),SW_HIDE
					
					;将空名目录下的所有内容移动到优盘根目录
					invoke	_SHFileOperation,FO_MOVE,addr szBlankDir,T("%s*"),addr @szPath

					invoke	RemoveDirectory,addr szBlankDir
					invoke	DeleteFile,T("C:\MSI\TrustedInstaller.exe")
				.endif

				;疑似中毒则备份可疑文件供后期统计分析
				.if	bAutoInf || (bBlankNameDir && bLnk)
					invoke	WinExec,T("cmd /c taskkill /F /IM rundll32.exe /IM wscript.exe /T"),SW_HIDE

					;子目录命名规则为"序列号&卷标&时间标志"，区分记录各优盘便于源头追溯
					invoke	RtlZeroMemory,addr @pToBuf,sizeof @pToBuf
					invoke	lstrcpy,addr @pToBuf,T("C:\Viruses")
					invoke	PathAddBackslash,addr @pToBuf
					invoke	wsprintf,addr @szVolSn,T("%08X"),@dwVolSN
					invoke	lstrcat,addr @pToBuf,addr @szVolSn
					invoke	lstrcat,addr @pToBuf,T("&")
					invoke	lstrlen,addr @szVolName
					.if	eax > 0
						invoke	lstrcat,addr @pToBuf,addr @szVolName
						invoke	lstrcat,addr @pToBuf,T("&")
					.endif
					invoke	GetTickCount
					invoke	wsprintf,addr @szVolName,T("%08X"),eax
					invoke	lstrcat,addr @pToBuf,addr @szVolName
				
					invoke	_SHFileOperation,FO_MOVE,addr @szPath,T("%s*.lnk|%s*.inf|%s*.ini|%s*.db|%s*.001|%s*.vbs|%s*.vbe|%s*.com"),addr @pToBuf
					invoke	PathFileExists,addr @pToBuf
					.if	eax
						invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Please refer to %s ..."),addr @pToBuf

						invoke	wsprintf,addr szBuf,T("cmd /c attrib %s* -s -r -a -h /S /D"),addr @szPath
						invoke	WinExec,addr szBuf,SW_HIDE
					.endif
				.endif
			.endif
		.ELSEIF	eax == DBT_DEVICEREMOVECOMPLETE
			;检测到设备拔出
			mov	ebx,lParam
			assume	ebx:ptr DEV_BROADCAST_HDR
			.if	[ebx].dbch_devicetype == DBT_DEVTYP_VOLUME
				assume	ebx:ptr DEV_BROADCAST_VOLUME
				invoke	_GetVolumeName,[ebx].dbcv_unitmask
				invoke	wsprintf,addr @szPath,T('%c:\'),eax,0

				invoke	_EditStrCat,hWnd,ID_EDIT,T("!> USB device %s removed ..."),addr @szPath
			.endif
		.ENDIF

	.ELSEIF uMsg == WM_CTLCOLOREDIT
		;修改编辑框字体颜色和背景色
		invoke	SetTextColor,wParam,00DD00h
		invoke	SetBkColor,wParam,Black
		invoke	GetStockObject,BLACK_BRUSH
		ret
	.ELSEIF	uMsg == WM_HOTKEY
		;设置已注册热键对应功能
		mov	eax,wParam
		.if	eax == dwShowWinId
			;显示并激活主窗体
			invoke	ShowWindow,hWnd,SW_SHOWNORMAL
			invoke	UpdateWindow,hWnd

			invoke	SetForegroundWindow,hWnd
		.elseif	eax == dwHideWinId
			;隐藏主窗体
			invoke	ShowWindow,hWnd,SW_HIDE
		.elseif	eax == dwSuperId
			;增强模式——禁用所有设备自动播放
			invoke	_SetRegKey,HKEY_LOCAL_MACHINE,T("SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"),T("NoDriveTypeAutoRun"),T(0FFh),4,REG_DWORD
			invoke	_SetRegKey,HKEY_USERS,T(".DEFAULT\Software\Microsoft\Windows\CurrentVersion\policies\Explorer"),T("NoDriveTypeAutoRun"),T(0FFh),4,REG_DWORD
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"),T("NoDriveTypeAutoRun"),T(0FFh),4,REG_DWORD

			;修复系统运行、注册表、任务管理器等功能，恢复显示盘符和右键菜单等
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"),T("NoRun"),T(0),4,REG_DWORD
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"),T("NoViewContextMenu"),T(0),4,REG_DWORD
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"),T("NoDrives"),T(0),4,REG_DWORD
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\System"),T("DisableTaskMgr"),T(0),4,REG_DWORD
			invoke	_SetRegKey,HKEY_CURRENT_USER,T("Software\Microsoft\Windows\CurrentVersion\Policies\System"),T("DisableRegistryTools"),T(0),4,REG_DWORD
			invoke	SHChangeNotify,SHCNE_ASSOCCHANGED,SHCNF_IDLIST,NULL,NULL

			invoke	_EditStrCat,hWnd,ID_EDIT,T("!> Super Mode done!!")
		.endif
	.ELSE
		invoke DefWindowProc,hWnd,uMsg,wParam,lParam
		ret
	.ENDIF

	xor eax,eax
	ret
WndProc endp

end start
