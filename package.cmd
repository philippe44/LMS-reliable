@echo off
SET version=0.2
rem SET type=stable
SET devroot=..\LMS-reliable
xcopy "%devroot%\CHANGELOG" "%devroot%\plugin" /y /d
CALL :zipxml %type%
goto :eof

:zipxml 
"c:\perl\bin\perl" ..\LMS\package.pl version "%devroot%" Reliable %version% %1
del "%devroot%\Reliable*.zip"
"C:\Program Files\7-Zip\7z.exe" a -r "%devroot%\Reliable-%version%.zip" "%devroot%\plugin\*"
"c:\perl\bin\perl" ..\LMS\package.pl sha "%devroot%" Reliable %version% %1
if %1 == stable xcopy "%devroot%\Reliable-%version%.zip" "%devroot%\..\LMS\" /y /d
goto :eof


