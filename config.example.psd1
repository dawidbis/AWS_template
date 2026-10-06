# Wzór konfiguracji. setup.cmd tworzy na jego podstawie config.psd1 (poza gitem).
@{
    # Profil z ~/.aws/config (aws configure list-profiles)
    Profile           = 'default'
    Region            = 'eu-central-1'

    # Jak odświeżać sesję (learn-login):
    #   'login' - aws login (konsolowe dane logowania)
    #   'sso'   - aws sso login (IAM Identity Center)
    #   'keys'  - stałe klucze z aws configure
    LoginMethod       = 'login'

    # Prefiks wszystkich zasobów tworzonych w labach. Komendy sprzątające działają tylko na nim.
    Prefix            = 'learn-'

    # Regexy nazw zasobów, których narzędzia NIGDY nie ruszają ani nie pokazują w aws-ls -All
    # (np. inny projekt na tym samym koncie). Przykład: @('^myproject-', '^prod-')
    ProtectedPatterns = @()

    # Runtime lambd w szablonach. Lokalny Python musi mieć tę samą wersję (sam build, testy).
    PythonRuntime     = 'python3.14'
}
