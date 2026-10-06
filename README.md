# AWS serverless – środowisko labów (Terraform + SAM + Python)

Szablon do nauki i prototypowania na AWS: każdy serwis najpierw „wyklikany” w konsoli, potem zapisany jako kod
(Terraform, opcjonalnie SAM), testowany i jedną komendą usuwany. Wszystko, co tworzą laby, ma wspólny prefiks
(domyślnie `learn-`), więc łatwo to znaleźć i posprzątać bez ryzyka dla innych zasobów na koncie.

## Wymagania

- Windows 10/11 z PowerShell 5.1+ (wbudowany) i **winget** (wbudowany w Windows 11)
- Konto AWS z uprawnieniami do IAM, Lambda, S3, CloudWatch Logs, CloudFormation (do nauki najprościej
  `AdministratorAccess` na własnym koncie) – **ustaw budżet z alertem w Billing**
- Resztę instaluje `setup.cmd`:

| Narzędzie | Wersja | |
|---|---|---|
| Git | any | wymagane |
| AWS CLI v2 | ≥ 2.32 | wymagane (`aws login`) |
| Terraform | ≥ 1.10 | wymagane |
| Python | 3.14 (= runtime lambd) | wymagane |
| AWS SAM CLI | | opcjonalne – laby z `-Sam` |
| Docker Desktop | | opcjonalne – `sam-local` |
| VS Code + `hashicorp.terraform`, `ms-python.python` | | zalecane |

## Start

```powershell
git clone <url-repo>
cd <repo>
.\setup.cmd
```

`setup.cmd`:
1. sprawdza narzędzia i proponuje instalację brakujących przez winget,
2. ustawia politykę skryptów PowerShell (RemoteSigned dla użytkownika), jeśli blokuje `.ps1`,
3. konfiguruje konto: wybór/utworzenie profilu AWS (`aws login`, SSO albo klucze), region, logowanie,
   prefiks zasobów i **ProtectedPatterns** – wzorce nazw innych projektów na koncie, których narzędzia nigdy nie ruszą,
4. zapisuje to w `config.psd1` (poza gitem; wzór: `config.example.psd1`),
5. tworzy `.venv` z `requirements-dev.txt` i instaluje rozszerzenia VS Code.

Ponowna konfiguracja: `.\setup.cmd -Reconfigure`. Bez pytań: `.\setup.cmd -Yes -AwsProfile dev -Region eu-west-1`.

Potem otwórz folder w VS Code – każdy nowy terminal (profil „AWS learn”) sam ładuje środowisko.
W innym terminalu: `. .\env.ps1`.

## Cykl pracy: konsola → kod → sprzątanie

```powershell
new-lab s3-trigger          # projects\NN-s3-trigger\ : NOTES.md + terraform\ (z -Sam także sam\)
```

1. **Konsola** – tworzysz serwis ręcznie, nazwy zaczynasz od prefiksu (`learn-s3-trigger...`).
   W `NOTES.md` notujesz, co konsola utworzyła sama (role, policy, log groupy, uprawnienia).
2. **Sprzątanie konsoli** – `aws-ls -All` pokazuje zasoby i kto nimi zarządza; `CONSOLE` = do usunięcia.
   - `rm-console-lambda <fn>` – lambda + jej rola + policy + log group
   - `rm-bucket <name>` – opróżnia (z wersjami) i usuwa bucket
3. **Terraform** – w folderze labu: `tf-up` (fmt + init + validate + apply) → `lambda-invoke <fn>` → `lab-test` → `tf-down`
4. **SAM** (opcjonalnie) – `sam-local` (Docker) → `sam-up` → `sam-down`

Komendy `tf-*` / `sam-*` uruchamiaj w folderze labu (`projects\NN-...`).

## Komendy (`learn-help`)

| Komenda | Co robi |
|---|---|
| `learn-check` / `learn-login` | stan narzędzi i sesji / logowanie profilu z configu |
| `new-lab <name> [-Sam] [-NoTf]` | nowy lab z `templates/` (+ `terraform init`) |
| `tf-up [-Plan] [-AutoApprove]` / `tf-down` | apply / destroy labu |
| `sam-up` / `sam-down` / `sam-local` | deploy / delete / lokalne wywołanie w Dockerze |
| `lab-test` | pytest dla labu |
| `lambda-invoke <fn> [event.json]` / `lambda-logs <fn>` | wywołanie z logiem / logi na żywo |
| `aws-ls [-All]` | zasoby labów (z `-All`: wszystko poza ProtectedPatterns) |
| `rm-console-lambda <fn>` / `rm-bucket <name>` | sprzątanie zasobów z konsoli |

## Struktura

| Ścieżka | Co |
|---|---|
| `setup.cmd`, `setup.ps1` | instalacja i konfiguracja |
| `config.example.psd1` → `config.psd1` | profil, region, prefiks, ProtectedPatterns, runtime |
| `env.ps1`, `tools/learn.psm1` | ładowanie środowiska, komendy |
| `templates/terraform` | lambda + rola + log group (retencja 3 dni), `default_tags`, lokalny state |
| `templates/sam` | ten sam szkielet w SAM + `samconfig.toml` |
| `projects/NN-name` | laby |
| `docs/roadmap.md` | przykładowa ścieżka labów (opcjonalna) |

### Wskazówka: import zamiast pisania od zera
Zanim usuniesz zasób z konsoli, możesz podejrzeć, jak wygląda w HCL: dodaj blok
`import { to = aws_lambda_function.this  id = "learn-x" }` i uruchom
`terraform plan -generate-config-out=generated.tf`. Traktuj wynik jako ściągę, potem usuń `import`
i zasób z konsoli, i postaw go od nowa przez `tf-up`.

## Koszty
Po każdej sesji: `aws-ls -All`. Pierwszy `sam-up` tworzy stack `aws-sam-cli-managed-default` (bucket na
artefakty SAM, współdzielony przez wszystkie laby) – można go zostawić.
