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
| `config/arquivos-atualizador.txt` | Arquivos do `overlay/` levados às máquinas já instaladas pelo `seduc_setup.sh` |
| `config/*.gpg` | Chaves públicas: repositório NetMonitor e atualizador do `seduc_setup.sh` |
| `debs/` | `.deb` extras (Epson, RustDesk, Web PKI, Central do Suporte em web) e `debs/instaladores/` (tokens e assinadores do painel); não versionados, veja `debs/LEIAME.txt` |
| `scripts/` | `seduc_setup.sh` publicado e assinado, baixado pelas máquinas instaladas |
| `tools/` | Ferramentas de manutenção |
| `overlay/usr/local/seduc/changelog` | O que mudou em cada versão |

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

O mesmo comando gera `scripts/seduc-arquivos.tar.gz`, também assinado, com os arquivos de
`config/arquivos-atualizador.txt`. A máquina aplica o pacote sempre que ele muda, menos
quando o sistema dela é mais novo que o pacote (ISO compilada depois).

```bash
tools/publicar-seduc-setup.sh <ID-da-chave> .
git add scripts/ && git commit -m "seduc_setup.sh X.Y-Z" && git push
```
