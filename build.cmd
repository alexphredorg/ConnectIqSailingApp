@echo off
echo va_hr
call monkeyc -o bin\SailingApp_vahr.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d vivoactive_hr
echo va3
call monkeyc -o bin\SailingApp_va3.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d vivoactive3