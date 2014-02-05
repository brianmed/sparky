#!/bin/bash

/usr/local/ActivePerl-5.16/bin/perl -MPOSIX -p -i -e '$t=POSIX::strftime("%Y-%m-%d", localtime); if (/=== START/ .. /=== STOP/ and !/START|STOP/) { $r=qr/"(\d+-\d+-\d+)\.(\d+)"/; m/$r/; $d=$1; $n=$2; $day{$d} = $n; $day{$t}++; $day{$t} = sprintf("%03d", $day{$t}); s/$r/"$t.$day{$t}"/; }' lib/Sparky.pm

\rm -f sparky.tgz
# tar -czf sparky.tgz includes ffmpeg/ffmpeg-osx
tar -czf sparky.tgz includes

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
# tar -czf sparky.tgz includes ffmpeg/ffmpeg-win32.exe
tar -czf sparky.tgz includes

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
tar -czf sparky.tgz includes

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
cp ../sparky-linux-x86-32 .
cp ../sparky-linux-x86-64 .
cp ../sparky-osx .
cp ../sparky-win32.exe .

cd ..
rm sparky.zip
zip sparky.zip "$VER"/*

cd "$VER"
rm ./INSTALL
rm ./INSTALL.txt
rm ./sparky-linux-x86-32
rm ./sparky-linux-x86-64
rm ./sparky-osx
rm ./sparky-win32.exe

cd ..
rmdir "$VER"
