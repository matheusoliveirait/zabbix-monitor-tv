# Politica de seguranca

## Versoes suportadas

Enquanto o projeto estiver em fase inicial, correcoes de seguranca serao
aplicadas somente na versao mais recente da branch principal.

## Relatando uma vulnerabilidade

Nao publique tokens, senhas, enderecos internos ou detalhes exploraveis em uma
issue publica. Use o recurso de relato privado de vulnerabilidade do GitHub
quando estiver habilitado no repositorio.

Inclua uma descricao do impacto, passos de reproducao e a versao afetada. O
recebimento sera confirmado assim que possivel e a correcao sera coordenada
antes da divulgacao publica.

## Boas praticas de implantacao

- Use um token Zabbix dedicado e com o menor privilegio necessario.
- Defina um `app_key` longo, aleatorio e exclusivo.
- Nao versione `config/app.php` ou dumps do banco.
- Publique o painel por HTTPS quando ele sair da rede local.
- Restrinja o admin por firewall, VPN ou proxy reverso.
- Mantenha PHP, Apache, MySQL/MariaDB e Zabbix atualizados.
