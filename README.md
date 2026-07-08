# HPro TV

Painel web para TV focado em visualizacao limpa de incidentes do Zabbix.

O projeto foi criado para substituir a visualizacao nativa do dashboard/widget do Zabbix em uma tela de NOC, mantendo a consulta alinhada ao widget "Incidentes Clientes" e priorizando legibilidade em TV.

## Recursos

- Consulta incidentes recentes via API do Zabbix.
- Filtra severidades Atencao, Media, Alta e Desastre.
- Ignora sintomas quando o modo de incidentes esta ativo.
- Ignora triggers, hosts e itens desativados.
- Exibe incidentes ativos e resolvidos recentes.
- Cards compactos para TV: Incidentes ativos, Desastre, Alta, Media e Atencao.
- Rodape rotativo no card principal com total, clientes afetados, maior duracao e resolvidos recentes.
- Ordenacao clicavel por hora, criticidade, cliente/host, problema e duracao.
- Paginacao automatica em grupos de 6 incidentes, com intervalo configuravel.
- Indicador NOVO para incidentes com menos de 10 minutos.
- Modo demo para validar layout sem conectar no Zabbix.

## Como usar

Abra `index.html` no navegador da TV ou publique o projeto em um servidor web interno.

## Estrutura

- `index.html`: estrutura da pagina.
- `styles.css`: estilos do painel.
- `app.js`: integracao com o Zabbix e comportamento da interface.
- `backups/index-completo-2026-07-08.html`: copia autocontida anterior a separacao.

Na primeira abertura, informe:

- URL da API do Zabbix, por exemplo `http://192.168.0.7/zabbix/api_jsonrpc.php`
- Token de API do Zabbix
- Intervalo de atualizacao
- Periodo de busca
- IDs de grupos ou hosts, se quiser limitar o escopo

As configuracoes ficam salvas apenas no `localStorage` do navegador. Nao coloque tokens diretamente no codigo antes de publicar o repositório.

## Modo demo

Para testar o layout sem Zabbix:

```text
index.html?demo=1
```

Para testar rolagem com mais eventos:

```text
index.html?demo=long
```

## Publicacao

Este projeto e estatico. Pode ser publicado em:

- GitHub Pages
- IIS, Nginx ou Apache interno
- Qualquer servidor que entregue arquivos HTML/CSS/JS

Se publicar via GitHub Pages, mantenha o repositório privado caso o painel seja apenas interno.
