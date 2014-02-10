#!/bin/bash

/usr/local/ActivePerl-5.16/bin/perl -MPOSIX -p -i -e '$t=POSIX::strftime("%Y-%m-%d", localtime); if (/=== START/ .. /=== STOP/ and !/START|STOP/) { $r=qr/"(\d+-\d+-\d+)\.(\d+)"/; m/$r/; $d=$1; $n=$2; $day{$d} = $n; $day{$t}++; $day{$t} = sprintf("%03d", $day{$t}); s/$r/"$t.$day{$t}"/; }' lib/Sparky.pm

\rm -f sparky.tgz
tar -czf sparky.tgz includes ffmpeg/ffmpeg-osx

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=/Users/bpm/Library/ActivePerl-5.16/lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
    --trim "B::Deparse" \
    --trim "CGI" \
    --trim "DBD::Pg" \
    --trim "Date::Calc::PP" \
    --trim "Math::BigFloat" \
    --trim "Mozilla::CA" \
    --trim "Mozilla::CA::*" \
    --trim "SQL::Parser" \
    --trim "SQL::Statement" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--force \
	--clean \
	--exe app/sparky-osx \
	--add "arybase;arybase;IO::Handle;Class::MethodMaker::scalar;DBD::SQLite" \
	--bind pDLNA.png[file=lib/PDLNA/pDLNA.png,mode=444] \
	--bind globs[file=globs,text,mode=464] \
	script/sparky

\rm -f sparky.tgz
tar -czf sparky.tgz includes ffmpeg/ffmpeg-win32.exe

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=/Users/bpm/Library/ActivePerl-5.16/lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
    --trim "B::Deparse" \
    --trim "CGI" \
    --trim "DBD::Pg" \
    --trim "Date::Calc::PP" \
    --trim "Math::BigFloat" \
    --trim "Mozilla::CA" \
    --trim "Mozilla::CA::*" \
    --trim "SQL::Parser" \
    --trim "SQL::Statement" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target windows-x86-32 \
	--force \
	--clean \
	--exe app/sparky-win32.exe \
	--add "arybase;arybase;IO::Handle;Class::MethodMaker::scalar;DBD::SQLite" \
	--bind pDLNA.png[file=lib/PDLNA/pDLNA.png,mode=444] \
	--bind globs[file=globs,text,mode=464] \
	script/sparky

rm ~/Downloads/spark/sparky-win32.exe 
cp -v app/sparky-win32.exe ~/Downloads/spark

\rm -f sparky.tgz
tar -czf sparky.tgz includes ffmpeg/ffmpeg-linux32

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "File::HomeDir::FreeDesktop" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=/Users/bpm/Library/ActivePerl-5.16/lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
    --trim "B::Deparse" \
    --trim "CGI" \
    --trim "DBD::Pg" \
    --trim "Date::Calc::PP" \
    --trim "Math::BigFloat" \
    --trim "Mozilla::CA" \
    --trim "Mozilla::CA::*" \
    --trim "SQL::Parser" \
    --trim "SQL::Statement" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target linux-x86-32 \
	--force \
	--clean \
	--exe app/sparky-linux-x86-32 \
	--add "arybase;arybase;IO::Handle;Class::MethodMaker::scalar;DBD::SQLite" \
	--bind pDLNA.png[file=lib/PDLNA/pDLNA.png,mode=444] \
	--bind globs[file=globs,text,mode=464] \
	script/sparky

\rm -f sparky.tgz
tar -czf sparky.tgz includes ffmpeg/ffmpeg-linux64

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "File::HomeDir::FreeDesktop" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=/Users/bpm/Library/ActivePerl-5.16/lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
    --trim "B::Deparse" \
    --trim "CGI" \
    --trim "DBD::Pg" \
    --trim "Date::Calc::PP" \
    --trim "Math::BigFloat" \
    --trim "Mozilla::CA" \
    --trim "Mozilla::CA::*" \
    --trim "SQL::Parser" \
    --trim "SQL::Statement" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target linux-x86-64 \
	--force \
	--clean \
	--exe app/sparky-linux-x86-64 \
	--add "arybase;arybase;IO::Handle;Class::MethodMaker::scalar;DBD::SQLite" \
	--bind pDLNA.png[file=lib/PDLNA/pDLNA.png,mode=444] \
	--bind globs[file=globs,text,mode=464] \
	script/sparky

VER=$(/usr/local/ActivePerl-5.16/bin/perl -MPOSIX -ne 'if (/=== START/ .. /=== STOP/ and !/START|STOP/) { $r=qr/"(\d+-\d+-\d+)\.(\d+)"/; m/$r/; print("$1.$2\n");}' lib/Sparky.pm)
VER="sparky-$VER"

cd app
mkdir "$VER"

cd "$VER"
cp ../INSTALL .
cp ../INSTALL.txt .
cp ../LICENSE .
cd ..

cd "$VER"
cp ../sparky-osx .
cd ..
rm sparky-osx.zip
zip sparky-osx.zip "$VER"/*

cd "$VER"
rm ./sparky-osx
cp ../sparky-win32.exe .
cd ..
rm sparky-win32.zip
zip sparky-win32.zip "$VER"/*

cd "$VER"
rm ./sparky-win32.exe
cp ../sparky-linux-x86-32 .
cd ..
rm sparky-linux32.zip
zip sparky-linux32.zip "$VER"/*

cd "$VER"
rm ./sparky-linux-x86-32
cp ../sparky-linux-x86-64 .
cd ..
rm sparky-linux64.zip
zip sparky-linux64.zip "$VER"/*

cd "$VER"
rm ./INSTALL
rm ./INSTALL.txt
rm ./LICENSE
rm ./sparky-linux-x86-64

cd ..
rmdir "$VER"
date
