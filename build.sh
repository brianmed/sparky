#!/bin/bash

\rm -f sparky.tgz
tar -czf sparky.tgz includes

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
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

/usr/local/PDK/bin/perlapp \
	--add "Mojo::;Mojolicious::;Sparky::;B::Hooks::EndOfScope::" \
    --add "Sparky::Index" \
    --add "Sparky::Dashboard" \
    --add "Sparky::Public" \
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
