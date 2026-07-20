# Central de Incidentes

Painel web open source para exibir incidentes do Zabbix em TVs e telas de NOC com leitura rapida, configuracao simples e sem dependencia do Grafana.

O projeto consulta a API oficial do Zabbix, protege o token no backend e apresenta somente as informacoes que importam durante a operacao. A interface foi desenhada para funcionar a distancia, com tipografia legivel, severidades claras e paginacao automatica.

> Projeto independente da comunidade. Nao e afiliado, patrocinado ou mantido pela Zabbix LLC.

## Recursos

- Consulta de incidentes recentes pela API do Zabbix.
- Backend PHP que evita expor o token no navegador.
- Login administrativo e configuracoes salvas em MySQL/MariaDB.
- Protecao do painel e das APIs para usuarios nao autenticados.
- Severidades Atencao, Media, Alta e Desastre.
- Filtro de sintomas, eventos suprimidos, hosts, triggers e itens inativos.
- Incidentes ativos e resolvidos recentemente.
- Ultimos dados validos preservados quando a API fica indisponivel.
- Ordenacao por hora, criticidade, cliente/host, problema e duracao.
- Paginacao automatica de seis incidentes com intervalo configuravel.
- Transicoes de pagina configuraveis: sem efeito, fade, deslizar ou zoom suave.
- Escala independente das fontes dos cards e da lista de incidentes.
- Destaques discretos para incidentes novos e resolvidos recentemente.
- Configuracao pelo botao no cabecalho ou pela tecla `F2`.
- Cenarios de demonstracao para validar o layout sem dados reais.

## Requisitos

- Apache ou outro servidor web compativel com PHP.
- PHP 8.1 ou superior, com PDO MySQL, cURL e OpenSSL.
- MySQL 8+ ou MariaDB 10.4+.
- Zabbix 7 ou versao compativel com os metodos utilizados.
- Token da API com acesso aos hosts e problemas monitorados.

## Instalacao rapida com XAMPP

1. Coloque o projeto em:

```text
C:\xampp\htdocs\zabbix-monitor-tv
```

2. Inicie Apache e MySQL no XAMPP.

3. Importe o banco:

```powershell
C:\xampp\mysql\bin\mysql.exe -u root < database\schema.sql
```

4. Crie a configuracao local a partir de `config/app.example.php`:

```text
config/app.example.php -> config/app.php
```

5. Defina as credenciais do banco e gere um `app_key` longo e exclusivo. Esse valor protege o token salvo.

6. Abra:

```text
http://localhost/zabbix-monitor-tv/
```

No primeiro acesso, o sistema encaminha para a criacao do administrador. Depois, informe a URL da API do Zabbix e o token.

Para uma TV na mesma rede:

```text
http://IP_DO_SERVIDOR/zabbix-monitor-tv/
```

## Configuracao do Zabbix

Use a URL completa do endpoint:

```text
http://zabbix.example.local/zabbix/api_jsonrpc.php
```

O usuario do token precisa enxergar os mesmos hosts e incidentes que devem aparecer na TV. IDs de grupos e hosts sao opcionais e podem limitar o escopo.

O token e criptografado antes de ser salvo no banco. O arquivo `config/app.php` e local e ignorado pelo Git.

## Demonstracao

Apos autenticar, acrescente um dos parametros abaixo ao endereco do painel:

```text
?demo=1       conjunto demonstrativo
?demo=long    varias paginas
?demo=single  um incidente
?demo=empty   nenhum incidente
```

Os cenarios usam apenas nomes ficticios.

## Estrutura

- `index.php`: protege e entrega o painel.
- `index.html`: interface para TV.
- `login.html`: primeiro acesso e autenticacao.
- `admin.php` e `admin.html`: protecao e interface de configuracoes.
- `app.js`, `login.js` e `admin.js`: comportamento do frontend.
- `dashboard.css`: layout responsivo e visual do painel para TV.
- `styles.css`: estilos das telas de login e configuracoes.
- `api/`: autenticacao, configuracoes e integracao com Zabbix.
- `database/schema.sql`: estrutura inicial do banco.
- `config/app.example.php`: modelo seguro da configuracao local.

## Seguranca

- Nao envie `config/app.php`, dumps ou tokens ao GitHub.
- Prefira HTTPS quando o painel for acessado fora de uma rede confiavel.
- Crie um token Zabbix dedicado, somente com as permissoes necessarias.
- Restrinja o acesso administrativo por firewall, VPN ou proxy reverso quando possivel.
- Consulte [SECURITY.md](SECURITY.md) para relatar vulnerabilidades.

## Contribuindo

Contribuicoes sao bem-vindas. Leia [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir uma issue ou pull request.

## Licenca

Distribuido sob a licenca MIT. Consulte [LICENSE](LICENSE).
