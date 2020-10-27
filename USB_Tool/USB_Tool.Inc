;--------------------------------------------------------------------------------
;程序作者：https://github.com/playGitboy/
;程序IDE：RadASM V2.x && MASM32 V6+
;功能简述：检测插入的移动存储设备是否感染LNK或AUTORUN病毒，如感染则自动修复并提取病毒文件以备统计分析
;注意事项：
;1.程序默认无界面运行，快捷键Win+O显示界面，Win+C再次隐藏，Win+S启动增强修复模式
;2.2015年的代码未更新，在win10中可能热键注册失败导致无法呼出界面，待修复……
;--------------------------------------------------------------------------------

;模式定义，定义程序使用的指令集、工作模式等
.386
.model flat,stdcall
option casemap:none

;引入用到的API相关头文件
include windows.inc
include dbt.inc
include user32.inc
include kernel32.inc
include	shell32.inc
include	shlwapi.inc
include	gdi32.inc
include advapi32.inc
include	psapi.inc

includelib user32.lib
includelib kernel32.lib
includelib shell32.lib
includelib shlwapi.lib
includelib gdi32.lib
includelib advapi32.lib
includelib psapi.lib

;从macros.asm中引用过来CTXT宏定义
literal MACRO quoted_text:VARARG
	LOCAL local_text
	.data
		local_text db quoted_text,0
		align 4
	.code
		EXITM <local_text>
ENDM

T MACRO quoted_text:VARARG
	EXITM <offset literal(quoted_text)>
ENDM

;常量定义
.const
	szShowHotKey	db	"MyShow",0
	szHideHotKey	db	"MyHide",0
	szSuperMode	db	"SuperMode",0

	ID_EDIT		equ	668

;初始化变量定义
.data
	szClassName	db	20 dup(0)

	bAutoInf	BOOL	FALSE
	bBlankNameDir	BOOL	FALSE
	bLnk		BOOL	FALSE

;未初始化变量定义
.data?
	hInstance	HINSTANCE	?

	dwShowWinId	dd		?
	dwHideWinId	dd		?
	dwSuperId		dd		?

	szMaxBuf	db	32000	 dup(?)

	szBuf		db	MAX_PATH dup(?)
	szBlankDir	db	MAX_PATH dup(?)

	dwTotalNum	dd	?,?
	dwFreeNum	dd	?,?
