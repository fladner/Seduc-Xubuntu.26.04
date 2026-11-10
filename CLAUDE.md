# Seduc Xubuntu 26.04

## Versionamento

Ajuste a versão por conta própria, sem esperar pedido, sempre que algo mudar no que
vai para as máquinas: `overlay/`, `config/`, `iso/`, `debs/`, `pacote/` ou `build.sh`.
Mudanças só no README ou em ferramentas de desenvolvimento não mudam a versão.

A versão `X.Y-Z` fica em `overlay/usr/local/seduc/version`, de onde o `build.sh` e o
`empacotar_deb.sh` a leem.

**Versão em aberto ou fechada:** uma versão fecha quando sua ISO é compilada ou quando
um `seduc_setup.sh` com essa versão é publicado. Enquanto estiver em aberto, as
mudanças entram na seção dela no changelog, sem trocar o número. Uma versão fechada
só pelo `seduc_setup.sh` ainda pode virar ISO com o mesmo número, desde que nada novo
tenha entrado depois; a mudança seguinte já abre a próxima versão.

**Que número usar, depois de uma versão fechada:**
- `Z + 1` (1.3-1 → 1.3-2): correções, pacotes acrescentados, ajustes e atualização de
  programas.
- `Y + 1` e `Z = 0` (1.3-2 → 1.4-0): recurso novo para o usuário, como um painel, um
  serviço ou uma integração nova, ou uma mudança grande no build.
- `X + 1`: só quando o usuário pedir.

**O que atualizar na mesma mudança:**
- `overlay/usr/local/seduc/version`.
- `overlay/usr/local/seduc/changelog`: seção `## X.Y-Z - dd/mm/aaaa` no topo, com uma
  linha por mudança, no estilo das seções anteriores.
- `SCRIPT_VERSION` de cada script de `overlay/usr/local/seduc/scripts/` alterado,
  igual à versão nova. Os scripts não alterados ficam com a versão que já têm.
- `config/arquivos-atualizador.txt`: arquivo novo ou alterado do `overlay/` que as
  máquinas já instaladas também precisam receber entra nessa lista (vai no pacote
  `scripts/seduc-arquivos.tar.gz` gerado pelo `tools/publicar-seduc-setup.sh`).
- `seduc_setup.sh`: as máquinas instaladas só aceitam um `SCRIPT_VERSION` maior do que
  o publicado. Antes de publicar, ele recebe a versão em aberto ou a próxima.

Na resposta ao usuário, diga em uma linha qual versão ficou e por quê. Commit, push e
publicação do `seduc_setup.sh` continuam só quando o usuário pedir.
