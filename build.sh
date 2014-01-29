#!/bin/bash

/usr/local/ActivePerl-5.16/bin/perl -MPOSIX -p -i -e '$t=POSIX::strftime("%Y-%m-%d", localtime); if (/=== START/ .. /=== STOP/ and !/START|STOP/) { $r=qr/"(\d+-\d+-\d+)\.(\d+)"/; m/$r/; $d=$1; $n=$2; $day{$d} = $n; $day{$t}++; $day{$t} = sprintf("%03d", $day{$t}); s/$r/"$t.$day{$t}"/; }' lib/Sparky.pm

\rm -f sparky.tgz
tar -czf sparky.tgz includes

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--force \
	--clean \
	--exe app/sparky-osx \
	script/sparky

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target windows-x86-32 \
	--force \
	--clean \
	--exe app/sparky-win32.exe \
	script/sparky

rm ~/Downloads/spark/sparky-win32.exe 
cp -v app/sparky-win32.exe ~/Downloads/spark

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target linux-x86-32 \
	--force \
	--clean \
	--exe app/sparky-linux-x86-32 \
	script/sparky

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
    --add "File::HomeDir" \
    --add "Crypt::Eksblowfish::Subkeyed" \
    --add "Compress::Zlib" \
	--bind "entities.txt[file=lib/Mojo/entities.txt,extract]" \
	--bind "sparky.tgz[file=sparky.tgz]" \
	--lib lib \
	--lib lib/Sparky \
	--norunlib \
	--target linux-x86-64 \
	--force \
	--clean \
	--exe app/sparky-linux-x86-64 \
	script/sparky

rm ~/Downloads/spark/sparky-win32.exe 
cp -v app/sparky-win32.exe ~/Downloads/spark
