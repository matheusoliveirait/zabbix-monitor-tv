# Como participar

Obrigado pelo interesse em melhorar a Central de Incidentes. O projeto recebe
relatos, ideias e perguntas da comunidade, enquanto o codigo oficial permanece
sob controle do mantenedor.

## Canais

- Use **Issues** para relatar erros reproduziveis.
- Use **Discussions** para ideias, perguntas, feedback e exemplos de uso.
- Nao envie dados reais de clientes, IPs internos, tokens, senhas ou logs sem
  anonimizar.

Antes de publicar, pesquise conversas existentes para evitar duplicidade.

## Pull requests

Pull requests sao aceitos somente de colaboradores autorizados ou depois de
alinhamento previo com o mantenedor. Uma sugestao aceita em uma Discussion ou
Issue nao garante que a implementacao sera incorporada.

Quando uma alteracao de codigo for combinada:

1. Crie uma branch a partir da `main`.
2. Configure o ambiente usando apenas os arquivos de exemplo.
3. Teste `?demo=empty`, `?demo=single` e `?demo=long`.
4. Valide os arquivos PHP e JavaScript alterados.
5. Descreva o objetivo, o impacto visual e os testes realizados.

## Padrao visual

O painel e uma ferramenta operacional para TV. Textos precisam ser legiveis a
distancia, controles devem ocupar pouco espaco e cores devem comunicar estado
sem competir com os incidentes.

## Relatos de seguranca

Nao abra uma Issue para vulnerabilidades exploraveis. Siga as orientacoes de
[SECURITY.md](SECURITY.md) e use o relato privado de vulnerabilidade do GitHub.
