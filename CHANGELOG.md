# Changelog

Todas as versoes publicas do Sword listadas aqui foram criadas por Lucas Lima (LucasLimaSzDev).

## v4.0 - 4.0

Versao operacional com metodos de monitoramento, relatorios e integracoes.

- Metodos de verificacao Ping/ICMP, TCP, HTTP e HTTPS.
- Cadastro de ativos com responsavel, tags, observacoes e manutencao.
- Relatorio de disponibilidade de 24h por ativo.
- Painel operacional com piores disponibilidades e incidentes abertos.
- Integracoes por webhook JSON para alertas criticos.

## v3.0 - 3.0

Primeira versao com identidade Sword e endurecimento de seguranca.

- Identidade visual Sword.
- CSRF em acoes de escrita.
- Rate limit de login.
- Headers defensivos e politica CSP.
- Auditoria administrativa, backup manual e exportacao controlada por cargo.

## v2.0 - 2.0

Evolucao do MVP com autenticacao, usuarios e papeis operacionais.

- Setup do primeiro administrador.
- Login e logout com sessao em cookie HttpOnly.
- Cargos de Administrador, Operador e Visualizador.
- Gestao de usuarios para administradores.
- Senhas com PBKDF2-SHA256 e salt individual.

## v1.0 - 1.0

Primeira versao publica do painel local de monitoramento de dispositivos.

- MVP web local para cadastro e monitoramento de dispositivos.
- Backend PowerShell com API HTTP e frontend estatico.
- Monitoramento por ICMP ping.
- Eventos de queda e retorno com duracao de indisponibilidade.
- Dashboard com indicadores, filtros, tabela, alertas e historico.

