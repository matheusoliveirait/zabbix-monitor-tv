# HPro TV

Painel web para TV focado em visualizacao limpa de incidentes do Zabbix.

O projeto substitui a visualizacao nativa do dashboard/widget do Zabbix em uma tela de NOC, mantendo a consulta alinhada ao widget "Incidentes Clientes" e priorizando legibilidade em TV.

## Recursos

- Consulta incidentes recentes via API do Zabbix.
- Backend PHP para proteger o token do Zabbix.
- Banco MySQL/MariaDB para usuarios e configuracoes.
- Login administrativo para configurar o painel.
- Bloqueia acesso ao painel e as APIs quando nao ha login ativo.
- Filtra severidades Atencao, Media, Alta e Desastre.
- Ignora sintomas quando o modo de incidentes esta ativo.
- Ignora triggers, hosts e itens desativados.
- Exibe incidentes ativos e resolvidos recentes.
- Mantem os ultimos dados bons na tela se a API falhar.
- Cards compactos para TV: Incidentes ativos, Desastre, Alta, Media e Atencao.
- Ordenacao clicavel por hora, criticidade, cliente/host, problema e duracao.
- Paginacao automatica em grupos de 6 incidentes, com intervalo configuravel.
- Acesso ao admin pelo `F2`.
- Modo demo para validar layout sem conectar no Zabbix.

## Requisitos

- XAMPP com PHP 8.1 ou superior.
- MySQL ou MariaDB.
- Token de API do Zabbix com permissao para consultar os mesmos hosts do widget atual.

## Estrutura

- `index.html`: painel da TV.
- `admin.html`: login e configuracoes.
- `styles.css`: estilos do painel e admin.
- `app.js`: comportamento do painel.
- `admin.js`: comportamento do admin.
- `api/`: backend PHP.
- `database/schema.sql`: estrutura do banco.
- `config/app.example.php`: exemplo de configuracao do backend.
- `config/app.php`: configuracao local ignorada pelo Git.
- `config.example.js`: exemplo de configuracao do frontend.
- `config.js`: configuracao local do frontend ignorada pelo Git.

## Instalar no XAMPP

1. Copie o projeto para uma pasta dentro do Apache:

```text
C:\xampp\htdocs\hpro-tv
```

2. Inicie Apache e MySQL no painel do XAMPP.

3. Importe o banco pelo phpMyAdmin ou pelo terminal:

```bash
C:\xampp\mysql\bin\mysql.exe -u root < database/schema.sql
```

4. Copie a configuracao do backend:

```text
config/app.example.php -> config/app.php
```

5. Edite `config/app.php` e troque pelo menos o `app_key`.

6. Acesse:

```text
http://localhost/hpro-tv/admin.html
```

7. Crie o primeiro usuario administrador.

8. Configure URL da API do Zabbix, token, intervalo e filtros.

9. Abra o painel:

```text
http://localhost/hpro-tv/
```

Na TV, use o IP da maquina onde esta o XAMPP:

```text
http://IP_DO_SERVIDOR/hpro-tv/
```

Sem login ativo, o painel redireciona para `admin.html`.

## Configuracao do Zabbix

No admin, informe:

- URL da API, por exemplo `http://zabbix.local/zabbix/api_jsonrpc.php`.
- Token de API do usuario que ja enxerga o widget/dash atual.
- Intervalo de atualizacao.
- IDs de grupos ou hosts se quiser limitar o escopo.

O token fica criptografado no banco. Nao coloque token real no repositorio.

## Modo demo

Para testar o layout sem Zabbix:

```text
index.html?demo=1
```

Para testar paginacao com mais eventos:

```text
index.html?demo=long
```

Para testar apenas um incidente:

```text
index.html?demo=single
```

Para testar a tela sem incidentes:

```text
index.html?demo=empty
```

## Publicar o projeto

Antes de deixar publico:

- Garanta que `config/app.php` nao foi versionado.
- Garanta que `config.js` nao foi versionado.
- Revise o historico para confirmar que nenhum token real foi enviado.
- Troque IPs internos dos exemplos por valores genericos.
- Adicione screenshots sem dados sensiveis.
- Adicione uma licenca, por exemplo MIT.
- Adicione uma nota de seguranca sobre tokens e exposicao de rede.

## Modo legado sem backend

O painel ainda suporta consulta direta pelo navegador para testes. Para isso, use `config.js` com:

```js
window.HPRO_CONFIG = {
  USE_BACKEND: false,
  ZABBIX_API_URL: "http://zabbix.local/zabbix/api_jsonrpc.php",
  ZABBIX_TOKEN: "TOKEN_DO_ZABBIX"
};
```

Esse modo nao e recomendado para uso publico, pois expoe o token no navegador.
