@echo off
if not exist rsvars_local.bat (goto exit2)

call rsvars_local.bat

@SET BDS=%BDS_LOCAL%
@SET BDSCOMMONDIR=%BDSCOMMONDIR_LOCAL%
@SET LAZARUS_LINUX=%LAZARUS_LINUX_LOCAL%
@SET FrameworkDir=%FrameworkDir_LOCAL%
@SET FrameworkVersion=%FrameworkVersion_LOCAL%
@SET FrameworkSDKDir=%FrameworkSDKDir_LOCAL%
@SET KaMOrigDir=%KaMOrigDir_LOCAL%
@SET KMRPrevVersionDir=%KMRPrevVersionDir_LOCAL%
@SET BuildFullDir=%BuildFullDir_LOCAL%
@SET ScriptingEditorDir=%ScriptingEditorDir_LOCAL%
@SET PATH=%FrameworkDir%;%FrameworkSDKDir%;%BDS%\bin;%BDS%\bin64;%PATH%
@SET kam_version=Beta

@SET IncludeScriptingEditor=False

goto exit0

:exit2
@echo !
@echo !
@echo ================================================================================
@echo ###########          FILE `RSVARS_LOCAL.BAT` NOT FOUND !!!!!         ###########
@echo ================================================================================
@echo !  
@echo !
@echo off
exit /B 2

:exit0
@echo off
exit /B 0