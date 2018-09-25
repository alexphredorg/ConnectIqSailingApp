@echo off
echo va_hr
call monkeyc -o bin\SailingApp_vahr.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d vivoactive_hr
echo va3
call monkeyc -o bin\SailingApp_va3.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d vivoactive3
echo va3m
call monkeyc -o bin\SailingApp_va3m.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d vivoactive3m
rem not yet, doesn't have touch
rem echo fenix5
rem call monkeyc -o bin\SailingApp_fenix5.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d fenix5
