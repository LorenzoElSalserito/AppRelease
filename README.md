# AppRelease
![Icon.png](Icon.png)
**English** · [🇮🇹 Leggi in italiano](#italiano) · [🇮🇹 Vai subito ai comandi di installazione](#agganciare-il-repository)

A GPG-signed Linux package repository. Hook it up once and my applications
behave like any other package on your system: they show up in `apt` / `dnf`, and
new versions arrive with your normal system update. No more hunting for a
download link at every release.

**Repository URL:** <https://lorenzoelsalserito.github.io/AppRelease/> — open it
to see which packages are currently published.

---

## Before you start

> 🇮🇹 [Questa sezione in italiano](#prima-di-cominciare)

You need `curl`, used below to download the signing key and the repository
configuration:

```bash
sudo apt install curl     # Debian, Ubuntu, Mint, Pop!_OS
sudo dnf install curl     # Fedora, RHEL, AlmaLinux, Rocky
sudo zypper install curl  # openSUSE
```

Every command below needs `sudo`, because it writes into `/etc`, where your
package manager keeps its list of trusted sources.

---

## Hook up the repository

> 🇮🇹 [Questa sezione in italiano](#agganciare-il-repository)

### Debian, Ubuntu, Linux Mint, Pop!\_OS (APT)

**Step 1 — install the signing key.**
Everything this repository serves is signed with a GPG key. Without its public
half, APT has no way to tell my packages from something a third party swapped in
along the way, and it will refuse the repository outright.

```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/public-key.asc \
  -o /etc/apt/keyrings/AppRelease.asc
sudo chmod 0644 /etc/apt/keyrings/AppRelease.asc
```

The key goes in `/etc/apt/keyrings/`, not in the old system-wide keyring: that
way it is trusted **for this repository only**, and it cannot be used to vouch
for anything else on your machine.

**Step 2 — add the source.**
This file tells APT where the repository lives and which key must have signed
it. It is a two-line download instead of a hand-written file, so no typos.

```bash
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.sources \
  -o /etc/apt/sources.list.d/AppRelease.sources
```

**Step 3 — refresh the package lists.**
APT downloads the repository index, checks its signature against the key from
step 1, and only then makes the packages available.

```bash
sudo apt update
```

If this command ends without warnings, you are done. Install anything you see on
the [repository page](https://lorenzoelsalserito.github.io/AppRelease/):

```bash
sudo apt install <package-name>
```

<details>
<summary>Debian 10 and earlier, Ubuntu 20.04 and earlier</summary>

The `.sources` format used in step 2 requires APT 2.4 or newer. On older systems
replace that step with the classic one-line format — it does exactly the same
thing:

```bash
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.list \
  -o /etc/apt/sources.list.d/AppRelease.list
sudo apt update
```
</details>

### Fedora, RHEL, CentOS Stream, AlmaLinux, Rocky (DNF)

```bash
# 1. Tell DNF where the repository is, and that both the index and the
#    individual packages must carry a valid signature.
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.repo \
  -o /etc/yum.repos.d/AppRelease.repo

# 2. Import the public key, so DNF can actually check those signatures.
sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc

# 3. Download the index and verify it.
sudo dnf makecache
```

Then install with:

```bash
sudo dnf install <package-name>
```

### openSUSE (zypper)

```bash
# 1. Import the public key first: zypper checks the repository as soon as it is added.
sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc

# 2. Add the repository with signature checking on and automatic refresh enabled.
sudo zypper addrepo --gpgcheck --refresh \
  https://lorenzoelsalserito.github.io/AppRelease/rpm AppRelease

# 3. Download the index.
sudo zypper refresh
```

Then `sudo zypper install <package-name>`.

---

## Getting updates

> 🇮🇹 [Questa sezione in italiano](#ricevere-gli-aggiornamenti)

Nothing else to configure. Once the repository is hooked up, your usual system
update also updates my applications:

```bash
sudo apt update && sudo apt upgrade     # Debian, Ubuntu, Mint, Pop!_OS
sudo dnf upgrade                        # Fedora, RHEL, AlmaLinux, Rocky
sudo zypper update                      # openSUSE
```

Graphical updaters (GNOME Software, Discover, KDE's updater…) read the same
configuration, so they will offer the new versions too.

---

## Checking the key before you trust it

> 🇮🇹 [Questa sezione in italiano](#controllare-la-chiave-prima-di-fidarti)

Adding a repository means letting it install software on your machine as root.
It is worth spending ten seconds on this check.

Print the fingerprint of the key you just downloaded:

```bash
curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/public-key.asc | gpg --show-keys
```

Compare it with the fingerprint shown at the bottom of the
[repository page](https://lorenzoelsalserito.github.io/AppRelease/). If the two
differ, stop and do not install anything: something between you and the server
is tampering with the download.

For reference, this is what gets verified and by whom:

| What | Verified by |
| --- | --- |
| The repository index (the list of available packages and their hashes) | `apt update` / `dnf makecache`, against the key you installed |
| Each `.rpm` package | `gpgcheck=1`, before installing |
| Each `.deb` package | `apt`, via the SHA256 hash recorded in the signed index |

---

## AppImage and other formats

> 🇮🇹 [Questa sezione in italiano](#appimage-e-altri-formati)

Files that are neither `.deb` nor `.rpm` — AppImage, `.tar.gz`, checksums —
cannot be managed by APT or DNF, so they are not part of the index and **will
not update automatically**. Download them by hand from the **Altri file**
section of the [repository page](https://lorenzoelsalserito.github.io/AppRelease/),
or from [Releases](../../releases), and re-download them when a new version
comes out.

For an AppImage, remember to make it executable after downloading:

```bash
chmod +x ./Whatever-1.0.0-x86_64.AppImage
./Whatever-1.0.0-x86_64.AppImage
```

---

## Removing the repository

> 🇮🇹 [Questa sezione in italiano](#rimuovere-il-repository)

Removing the repository stops the updates; it does **not** uninstall packages
you already installed. Uninstall those first if you want them gone
(`sudo apt remove <package-name>` / `sudo dnf remove <package-name>`).

```bash
# Debian, Ubuntu, Mint, Pop!_OS — drop the source and the key, then refresh
sudo rm -f /etc/apt/sources.list.d/AppRelease.sources \
           /etc/apt/sources.list.d/AppRelease.list \
           /etc/apt/keyrings/AppRelease.asc
sudo apt update
```

```bash
# Fedora, RHEL, AlmaLinux, Rocky — drop the repository and clear its cache
sudo rm -f /etc/yum.repos.d/AppRelease.repo
sudo dnf clean all
```

```bash
# openSUSE
sudo zypper removerepo AppRelease
```

On RPM systems the public key stays in the RPM keyring even after the repository
is gone. To remove it as well, find its entry and delete it:

```bash
rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
sudo rpm -e gpg-pubkey-XXXXXXXX-YYYYYYYY   # the line mentioning AppRelease
```

---

## If something goes wrong

> 🇮🇹 [Questa sezione in italiano](#se-qualcosa-non-funziona)

| Message | What it means | Fix |
| --- | --- | --- |
| `NO_PUBKEY` / `is not signed` | APT has no key for this repository, or the wrong one | Redo step 1, then `sudo apt update` |
| `Release file ... is not valid yet` | Your clock is behind the server's | `sudo timedatectl set-ntp true`, then retry |
| `repomd.xml GPG signature verification error` | The key was never imported into RPM | `sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc` |
| `404 Not Found` on `apt update` | The URL was mistyped, or the repository has no packages yet | Open the [repository page](https://lorenzoelsalserito.github.io/AppRelease/) and check |
| The package installs but never updates | Your architecture is not published, or you installed the AppImage instead of the `.deb`/`.rpm` | Check with `apt policy <package-name>` / `dnf info <package-name>` |

---

## License

> 🇮🇹 [Questa sezione in italiano](#licenza)

This distribution repository is covered by [LICENSE](LICENSE). Each published
package keeps its own licence.

---
---

# Italiano

[↑ Back to English](#apprelease)

Repository di pacchetti Linux firmato GPG. Lo agganci una volta e le mie
applicazioni si comportano come qualsiasi altro pacchetto del tuo sistema:
compaiono in `apt` / `dnf` e le nuove versioni arrivano con il normale
aggiornamento di sistema. Basta cercare il link di download a ogni release.

**URL del repository:** <https://lorenzoelsalserito.github.io/AppRelease/> —
aprilo per vedere quali pacchetti sono pubblicati in questo momento.

---

## Prima di cominciare

Ti serve `curl`, che nei comandi qui sotto scarica la chiave di firma e la
configurazione del repository:

```bash
sudo apt install curl     # Debian, Ubuntu, Mint, Pop!_OS
sudo dnf install curl     # Fedora, RHEL, AlmaLinux, Rocky
sudo zypper install curl  # openSUSE
```

Tutti i comandi che seguono richiedono `sudo`, perché scrivono dentro `/etc`,
dove il gestore di pacchetti tiene l'elenco delle sorgenti di cui si fida.

---

## Agganciare il repository

### Debian, Ubuntu, Linux Mint, Pop!\_OS (APT)

**Passo 1 — installa la chiave di firma.**
Tutto ciò che questo repository serve è firmato con una chiave GPG. Senza la sua
metà pubblica, APT non ha modo di distinguere i miei pacchetti da qualcosa che
qualcun altro abbia sostituito lungo il percorso, e rifiuterà il repository.

```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/public-key.asc \
  -o /etc/apt/keyrings/AppRelease.asc
sudo chmod 0644 /etc/apt/keyrings/AppRelease.asc
```

La chiave finisce in `/etc/apt/keyrings/`, non nel vecchio portachiavi di
sistema: così vale **solo per questo repository** e non può garantire per nient'altro
installato sulla tua macchina.

**Passo 2 — aggiungi la sorgente.**
Questo file dice ad APT dove si trova il repository e quale chiave deve averlo
firmato. Si scarica invece di scriverlo a mano, così non ci sono errori di
battitura.

```bash
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.sources \
  -o /etc/apt/sources.list.d/AppRelease.sources
```

**Passo 3 — aggiorna gli elenchi dei pacchetti.**
APT scarica l'indice del repository, ne verifica la firma con la chiave del
passo 1 e solo allora rende disponibili i pacchetti.

```bash
sudo apt update
```

Se il comando finisce senza avvisi, hai finito. Installa quello che vedi sulla
[pagina del repository](https://lorenzoelsalserito.github.io/AppRelease/):

```bash
sudo apt install <nome-pacchetto>
```

<details>
<summary>Debian 10 e precedenti, Ubuntu 20.04 e precedenti</summary>

Il formato `.sources` del passo 2 richiede APT 2.4 o superiore. Sui sistemi più
vecchi sostituisci quel passo con il formato classico a riga singola, che fa
esattamente la stessa cosa:

```bash
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.list \
  -o /etc/apt/sources.list.d/AppRelease.list
sudo apt update
```
</details>

### Fedora, RHEL, CentOS Stream, AlmaLinux, Rocky (DNF)

```bash
# 1. Dice a DNF dove sta il repository e che sia l'indice sia i singoli
#    pacchetti devono avere una firma valida.
sudo curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/apprelease.repo \
  -o /etc/yum.repos.d/AppRelease.repo

# 2. Importa la chiave pubblica, senza la quale DNF non può verificare nulla.
sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc

# 3. Scarica l'indice e lo verifica.
sudo dnf makecache
```

Poi installa con:

```bash
sudo dnf install <nome-pacchetto>
```

### openSUSE (zypper)

```bash
# 1. Prima la chiave pubblica: zypper controlla il repository appena lo aggiungi.
sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc

# 2. Aggiunge il repository con verifica della firma e aggiornamento automatico.
sudo zypper addrepo --gpgcheck --refresh \
  https://lorenzoelsalserito.github.io/AppRelease/rpm AppRelease

# 3. Scarica l'indice.
sudo zypper refresh
```

Poi `sudo zypper install <nome-pacchetto>`.

---

## Ricevere gli aggiornamenti

Non c'è altro da configurare. Una volta agganciato il repository, il tuo solito
aggiornamento di sistema aggiorna anche le mie applicazioni:

```bash
sudo apt update && sudo apt upgrade     # Debian, Ubuntu, Mint, Pop!_OS
sudo dnf upgrade                        # Fedora, RHEL, AlmaLinux, Rocky
sudo zypper update                      # openSUSE
```

Anche gli aggiornatori grafici (GNOME Software, Discover, e simili) leggono la
stessa configurazione, quindi ti proporranno le nuove versioni.

---

## Controllare la chiave prima di fidarti

Aggiungere un repository significa permettergli di installare software sulla tua
macchina con i privilegi di root. Vale la pena spenderci dieci secondi.

Stampa l'impronta della chiave che hai appena scaricato:

```bash
curl -fsSL https://lorenzoelsalserito.github.io/AppRelease/public-key.asc | gpg --show-keys
```

Confrontala con l'impronta mostrata in fondo alla
[pagina del repository](https://lorenzoelsalserito.github.io/AppRelease/). Se le
due non coincidono, fermati e non installare niente: qualcosa fra te e il server
sta manomettendo il download.

Per riferimento, ecco che cosa viene verificato e da chi:

| Cosa | Verificato da |
| --- | --- |
| L'indice del repository (elenco dei pacchetti e relativi hash) | `apt update` / `dnf makecache`, con la chiave che hai installato |
| Ogni pacchetto `.rpm` | `gpgcheck=1`, prima dell'installazione |
| Ogni pacchetto `.deb` | `apt`, tramite l'hash SHA256 scritto nell'indice firmato |

---

## AppImage e altri formati

I file che non sono `.deb` né `.rpm` — AppImage, `.tar.gz`, checksum — non
possono essere gestiti da APT o DNF, quindi non fanno parte dell'indice e **non
si aggiornano da soli**. Scaricali a mano dalla sezione **Altri file** della
[pagina del repository](https://lorenzoelsalserito.github.io/AppRelease/) oppure
da [Releases](../../releases), e riscaricali quando esce una nuova versione.

Se è un AppImage, ricordati di renderlo eseguibile dopo il download:

```bash
chmod +x ./Qualcosa-1.0.0-x86_64.AppImage
./Qualcosa-1.0.0-x86_64.AppImage
```

---

## Rimuovere il repository

Rimuovere il repository interrompe gli aggiornamenti, ma **non** disinstalla i
pacchetti che hai già installato. Se vuoi togliere anche quelli, disinstallali
prima (`sudo apt remove <nome-pacchetto>` / `sudo dnf remove <nome-pacchetto>`).

```bash
# Debian, Ubuntu, Mint, Pop!_OS — togli sorgente e chiave, poi aggiorna
sudo rm -f /etc/apt/sources.list.d/AppRelease.sources \
           /etc/apt/sources.list.d/AppRelease.list \
           /etc/apt/keyrings/AppRelease.asc
sudo apt update
```

```bash
# Fedora, RHEL, AlmaLinux, Rocky — togli il repository e svuota la sua cache
sudo rm -f /etc/yum.repos.d/AppRelease.repo
sudo dnf clean all
```

```bash
# openSUSE
sudo zypper removerepo AppRelease
```

Sui sistemi RPM la chiave pubblica resta nel portachiavi di RPM anche dopo aver
tolto il repository. Per rimuovere anche quella, individua la sua voce ed
eliminala:

```bash
rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
sudo rpm -e gpg-pubkey-XXXXXXXX-YYYYYYYY   # la riga che riporta AppRelease
```

---

## Se qualcosa non funziona

| Messaggio | Che cosa significa | Rimedio |
| --- | --- | --- |
| `NO_PUBKEY` / `non è firmato` | APT non ha la chiave di questo repository, o ne ha una sbagliata | Rifai il passo 1, poi `sudo apt update` |
| `Il file Release ... non è ancora valido` | L'orologio del tuo computer è indietro rispetto al server | `sudo timedatectl set-ntp true`, poi riprova |
| `repomd.xml GPG signature verification error` | La chiave non è mai stata importata in RPM | `sudo rpm --import https://lorenzoelsalserito.github.io/AppRelease/public-key.asc` |
| `404 Not Found` durante `apt update` | URL scritto male, oppure il repository non ha ancora pacchetti | Apri la [pagina del repository](https://lorenzoelsalserito.github.io/AppRelease/) e controlla |
| Il pacchetto si installa ma non si aggiorna mai | La tua architettura non è pubblicata, oppure hai installato l'AppImage invece del `.deb`/`.rpm` | Controlla con `apt policy <nome-pacchetto>` / `dnf info <nome-pacchetto>` |

---

## Licenza

Questo repository di distribuzione è coperto da [LICENSE](LICENSE). Ogni
pacchetto pubblicato mantiene la propria licenza.
