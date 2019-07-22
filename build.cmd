@echo off
set devices=vivoactive3 vivoactive3m vivoactive3d fenix5 fenix5plus fenix5splus fenix5x fenix5xplus fr245 fr245m fr645 fr645m fr935 fr945
if not "%1"=="" set devices=%1
for %%d in (%devices%) do echo %%d && call monkeyc -o bin\SailingApp_%%d.prg -w -y ..\developer_key -f .\SailingApp.jungle --warn -d %%d
