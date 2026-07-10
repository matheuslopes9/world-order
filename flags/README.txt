BANDEIRAS OFICIAIS (SVG)
========================

Fonte:   https://github.com/hampusborgos/country-flags
         (renders precisos das bandeiras oficiais, arquivos originais
         da Wikimedia Commons)
Licença: Domínio público — bandeiras nacionais não são protegidas por
         copyright. Uso comercial livre.

Nomeação: código ISO 3166-1 alpha-2 minúsculo (br.svg, us.svg, ...)
— casa com o campo `codigo_iso` das nações do jogo.

Integração: WorldMap._paint_flag() usa estes SVGs automaticamente;
se um código não tiver arquivo, cai no desenho aproximado por listras
(FlagData.gd). O Godot 4 importa SVG nativamente (nítido em qualquer zoom).
