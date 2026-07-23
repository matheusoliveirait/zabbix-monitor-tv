# Central de Incidentes

Painel web open source para exibir incidentes do Zabbix em TVs e telas de NOC com leitura rapida, configuracao simples e sem dependencia do Grafana.

O projeto consulta a API oficial do Zabbix, protege o token no backend e apresenta somente as informacoes que importam durante a operacao. A interface foi desenhada para funcionar a distancia, com tipografia legivel, severidades claras e paginacao automatica.

> Projeto independente da comunidade. Nao e afiliado, patrocinado ou mantido pela Zabbix LLC.

![Previa da Central de Incidentes](assets/social-preview.png)

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
- Temas Chumbo, Claro e Azul selecionaveis nas configuracoes, com Chumbo como padrao.
- Cores de criticidade personalizaveis com contraste automatico e restauracao da paleta padrao.
- Escala independente das fontes dos cards e da lista de incidentes, de 85% a 200% em passos de 5%.
- Ajuste rapido de fontes no proprio painel, com previa antes de aplicar.
- Destaques discretos para incidentes novos e resolvidos recentemente.
- Configuracao pelo botao no cabecalho ou pela tecla `F2`.
- Cenarios de demonstracao para validar o layout sem dados reais.

## Requisitos

- Apache ou Nginx.
- PHP 8.1 ou superior, com PDO MySQL, cURL e OpenSSL.
- MySQL 8+ ou MariaDB 10.4+.
- Zabbix 7 ou versao compativel com os metodos utilizados.
- Token da API com acesso aos hosts e problemas monitorados.

## Instalacao automatizada no Linux

O instalador oferece suporte inicial a Ubuntu e Debian. Baixe o script da release, revise e execute:

> No Windows, ter `wget` instalado permite baixar o arquivo, mas `install.sh` continua sendo exclusivo para Linux. Para Windows, siga a instalacao com XAMPP descrita abaixo.

```bash
wget https://github.com/matheusoliveirait/zabbix-monitor-tv/releases/latest/download/install.sh
less install.sh
chmod +x install.sh
sudo ./install.sh
```

Ele prepara PHP, MariaDB, Apache ou Nginx, instala os arquivos e apresenta a URL do assistente com um codigo temporario:

```text
Servidor preparado com sucesso.

  Acesse:  http://192.168.1.50/setup/
  Codigo:  A1B2-C3D4
```

O codigo expira em duas horas. No navegador, o assistente valida o ambiente, prepara as tabelas, cria o administrador, testa o Zabbix e bloqueia o instalador.

Para escolher o servidor sem perguntas:

```bash
sudo ./install.sh --apache --non-interactive
sudo ./install.sh --nginx --non-interactive
sudo ./install.sh --apache --port 8090 --non-interactive
```

Quando nenhuma porta e informada, o instalador procura uma porta livre nesta ordem: `80`, `8080`, `8081` e `8888`. Uma porta especifica pode ser escolhida com `--port`; se estiver ocupada, a instalacao e interrompida sem alterar o servico existente. A porta `443` deve ser configurada depois com HTTPS e certificado em um proxy reverso.

Use `--help` para consultar dominio, diretorio, versao, porta e banco externo. O script inicial nao sobrescreve instalacoes existentes.

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
- `assets/`: identidade visual e favicon do sistema.
- `dashboard.css`: layout responsivo e visual do painel para TV.
- `styles.css`: estilos das telas de login e configuracoes.
- `api/`: autenticacao, configuracoes e integracao com Zabbix.
- `database/schema.sql`: estrutura inicial do banco.
- `database/schema.php`: estrutura executada de forma segura pelo assistente.
- `config/app.example.php`: modelo seguro da configuracao local.
- `setup/`: instalador web protegido por codigo temporario.
- `deploy/`: modelos revisaveis para Apache e Nginx.
- `install.sh`: preparacao automatizada para Ubuntu e Debian.

## Seguranca

- Nao envie `config/app.php`, dumps ou tokens ao GitHub.
- Nao compartilhe o codigo temporario exibido pelo instalador.
- Prefira HTTPS quando o painel for acessado fora de uma rede confiavel.
- Crie um token Zabbix dedicado, somente com as permissoes necessarias.
- Restrinja o acesso administrativo por firewall, VPN ou proxy reverso quando possivel.
- Consulte [SECURITY.md](SECURITY.md) para relatar vulnerabilidades.

## Comunidade

- Use [Issues](https://github.com/matheusoliveirait/zabbix-monitor-tv/issues) para relatar erros.
- Use [Discussions](https://github.com/matheusoliveirait/zabbix-monitor-tv/discussions) para ideias, perguntas e sugestoes.
- Pull requests sao aceitos somente de colaboradores autorizados ou depois de alinhamento previo.

Leia [CONTRIBUTING.md](CONTRIBUTING.md) antes de publicar dados, telas ou logs.

## Licenca

Distribuido sob a licenca MIT. Consulte [LICENSE](LICENSE).
