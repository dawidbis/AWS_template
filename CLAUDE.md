# Kontekst dla Claude

Repo do nauki i prototypowania AWS serverless (Python lambdy, Terraform, SAM). Odpowiadaj po polsku.

- Ustawienia konta są w `config.psd1` (profil, region, prefiks, ProtectedPatterns), wzór w `config.example.psd1`.
  Zasoby z ProtectedPatterns NIGDY nie modyfikuj ani nie usuwaj.
- Zasoby labów mają prefiks z `config.psd1` i tag `Purpose=learning`. Przy NoCredentials poproś o `learn-login`.
- Cykl: nowy serwis najpierw w konsoli (robi to użytkownik), potem HCL w `projects/NN-name/terraform`, zasób z konsoli usunięty.
- Nowe laby powstają z `templates/` przez `new-lab` (tools/learn.psm1). Placeholdery: `__LAB__`, `__NAME__`,
  `__PREFIX__`, `__PROFILE__`, `__REGION__`, `__RUNTIME__`.
- Pliki `.ps1`/`.psm1` zapisuj jako UTF-8 z BOM (Windows PowerShell 5.1 + polskie znaki), a `.cmd` tylko w ASCII.
- Lokalny kontekst użytkownika (konto, inne projekty) jest w `CLAUDE.local.md`, poza gitem.
