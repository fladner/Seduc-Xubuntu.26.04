# Seduc Xubuntu 26.04

Customização da ISO do Xubuntu 26.04 usada nos computadores da SEDUC.
O `build.sh` parte da ISO anterior, aplica as mudanças deste repositório e gera uma ISO nova.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `build.sh` | Gera a ISO (precisa de root e internet) |
| `overlay/` | Arquivos copiados por cima do sistema, com os mesmos caminhos (`/etc`, `/usr/local/seduc`...) |
| `iso/` | Arquivos que substituem os da ISO no mesmo caminho (menu de boot `boot/grub/`) |
| `overlay/usr/local/seduc/central.d/` | Itens da Central do Suporte, um `.desktop` por item (veja o `LEIAME` da pasta) |
| `config/pacotes-instalar.txt` | Pacotes instalados no build |
| `config/pacotes-base-xubuntu.txt` | Infraestrutura do Xubuntu completo, sem programas novos no menu |
| `config/pacotes-remover.txt` | Pacotes removidos no build |
| `config/arquivos-remover.txt` | Arquivos apagados da imagem |
| `config/debs-atualizador.txt` | `.deb` criados para a ISO que o `seduc_setup.sh` instala nas máquinas já instaladas |
| `config/*.gpg` | Chaves públicas: repositório NetMonitor e atualizador do `seduc_setup.sh` |
| `debs/` | `.deb` extras (Epson, RustDesk, Web PKI, Central do Suporte em web) e `debs/instaladores/` (tokens e assinadores do painel); não versionados, veja `debs/LEIAME.txt` |
| `scripts/` | `seduc_setup.sh`, pacotes do sistema e `.deb` nossos, publicados e assinados para as máquinas instaladas |
| `tools/` | Ferramentas de manutenção |
| `overlay/usr/local/seduc/changelog` | O que mudou em cada versão |

## Atualização automática dos pacotes

Desde a 1.7-0 quem atualiza os programas é o `seduc-atualizar.timer`, com o
`overlay/usr/local/seduc/scripts/atualizar_pacotes.sh`, no lugar do unattended-upgrades
(o apt-daily fica desligado). Atualiza a cada 3 dias, logo depois de ligar (1 dia depois,
se faltou algo), com `full-upgrade` de todos os repositórios mantendo as configurações da
SEDUC; um pacote que o proxy barra fica para a próxima vez sem cancelar os outros. O
resultado fica em `/var/lib/seduc-atualizar/status` (mostrado em "Atualizar o sistema"
na Central) e o log em `/usr/local/seduc/logs/atualizacao_automatica.log`.

## Gerar a ISO

1. Coloque os `.deb` de `debs/LEIAME.txt` em `debs/`.
2. Ajuste a versão em `overlay/usr/local/seduc/version` e o `changelog`.
3. Rode:

```bash
sudo ./build.sh [ISO_BASE] [VERSAO]
```

A ISO sai em `out/`, com o `.sha256` ao lado. Por padrão a base é
`base/xubuntu-seduc-26.04-v1.3-1-amd64.iso` (a pasta `base/` fica fora do Git).

## Publicar uma versão nova do seduc_setup.sh

As máquinas instaladas baixam `scripts/seduc_setup.sh` deste repositório no boot e só
aplicam se a assinatura GPG conferir com `config/seduc-updates.gpg` e a versão for maior.

O mesmo comando gera, também assinado, `scripts/seduc-sistema.tar.gz`: o `overlay/`
inteiro, com a versão, as listas de pacotes de `config/` e o sha256 dos `.deb` de
`config/debs-atualizador.txt` (copiados para `scripts/debs/`). A máquina aplica o pacote
sempre que ele muda, menos quando o sistema dela é mais novo (ISO compilada depois),
instala os `.deb` com versão maior e os pacotes da ISO que faltam. Assim a máquina
instalada fica igual à ISO nova. Os `.deb` de terceiros vêm pelos canais oficiais.
`scripts/seduc-arquivos.tar.gz` é a parte do overlay que os `seduc_setup.sh` até 1.6-2
aceitam, para eles já receberem os scripts antes de se atualizarem.

```bash
tools/publicar-seduc-setup.sh <ID-da-chave> .
git add -A scripts/ && git commit -m "seduc_setup.sh X.Y-Z" && git push
```
