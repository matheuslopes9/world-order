# 🌍 Mapa do Jogo — Nations: New Dawn

Mapa de arquitetura interativo do jogo, gerado a partir do código GDScript real
(43 scripts, 1.328 símbolos, 68 dependências) com o [Graphify](https://github.com/Graphify-Labs/graphify).

## Como abrir (100% offline)

Basta dar **duplo-clique** em [`mapa_do_jogo.html`](mapa_do_jogo.html) — ele abre em
qualquer navegador **sem internet**. O arquivo é autossuficiente: todo o CSS e
JavaScript estão embutidos, sem nenhuma dependência externa (nenhum CDN, fonte
remota ou script online).

O que dá pra fazer no mapa:
- **Arrastar** os nós do grafo pra reorganizar
- **Passar o mouse** sobre um nó pra destacar suas conexões
- Ver a arquitetura organizada nas **7 camadas** (motor, nação, IA, subsistemas,
  interface, persistência, testes)

## Como atualizar depois de mexer no código

O mapa reflete o commit em que foi gerado. Para regerar com o código atual:

```bash
# na raiz do projeto — extrai o código de novo (local, sem custo de API)
graphify update .
# depois copie o HTML regenerado do artifact/scratchpad para cá, OU regere
# o graph.json e reconstrua o mapa a partir dele
```

> **Nota:** a pasta `graphify-out/` (onde o Graphify escreve `graph.json`,
> `graph.html` e o relatório) está no `.gitignore` por ser gerada. Este
> `docs/mapa/` é a cópia **versionada e permanente** do mapa, que fica no repo.
