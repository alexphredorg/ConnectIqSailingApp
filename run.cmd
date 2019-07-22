@echo off
set device=vivoactive3
set binary=va3
if not "%1"=="" set device=%1
if not "%1"=="" set binary=%1
echo using device %device%
echo using binary bin\SailingApp_%binary%.prg
monkeydo bin\SailingApp_%binary%.prg %device%
