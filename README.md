# HPro TV

Painel web para TV focado em visualizacao limpa de incidentes do Zabbix.

O projeto substitui a visualizacao nativa do dashboard/widget do Zabbix em uma tela de NOC, mantendo a consulta alinhada ao widget "Incidentes Clientes" e priorizando legibilidade em TV.

## Recursos

- Consulta incidentes recentes via API do Zabbix.
- Filtra severidades Atencao, Media, Alta e Desastre.
- Ignora sintomas quando o modo de incidentes esta ativo.
- Ignora triggers, hosts e itens desativados.
- Exibe incidentes ativos e resolvidos recentes.
- Mantem os ultimos dados bons na tela se a API falhar.
- Cards compactos para TV: Incidentes ativos, Desastre, Alta, Media e Atencao.
- Ordenacao clicavel por hora, criticidade, cliente/host, problema e duracao.
- Paginacao automatica em grupos de 6 incidentes, com intervalo configuravel.
- Acesso as configuracoes por F2, sem poluir o painel da TV.
- Modo demo para validar layout sem conectar no Zabbix.

## Como usar

Publique a pasta em um servidor web interno ou rode um servidor estatico local.

Exemplo rapido:

```bash
python3 -m http.server 8765
```

Depois acesse:

```text
http://IP_DO_SERVIDOR:8765/
```

## Estrutura

- `index.html`: estrutura da pagina.
- `styles.css`: estilos do painel.
- `app.js`: integracao com o Zabbix e comportamento da interface.
- `config.example.js`: modelo de configuracao local.
- `config.js`: configuracao local ignorada pelo Git.
- `backups/index-completo-2026-07-08.html`: copia autocontida anterior a separacao.

## Configuracao

Copie `config.example.js` para `config.js` e preencha:

```js
window.HPRO_CONFIG = {
  ZABBIX_API_URL: "http://192.168.0.7/zabbix/api_jsonrpc.php",
  ZABBIX_TOKEN: "TOKEN_DO_ZABBIX",
  REFRESH_SECONDS: 10,
  API_LIMIT: 500,
  PAGE_INTERVAL_SECONDS: 15,
  SORT_MODE: "recent",
  FETCH_MODE: "incidents",
  MONITORED_GROUP_IDS: [],
  MONITORED_HOST_IDS: []
};
```

Tambem e possivel abrir as configuracoes pelo painel pressionando `F2`. As configuracoes salvas pela interface ficam no `localStorage` do navegador.

Nao publique tokens diretamente no repositorio.

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

## Publicacao

Este projeto e estatico. Pode ser publicado em:

- GitHub Pages
- IIS, Nginx ou Apache interno
- Qualquer servidor que entregue arquivos HTML/CSS/JS

Se publicar via GitHub Pages, mantenha o repositorio privado caso o painel seja apenas interno.
