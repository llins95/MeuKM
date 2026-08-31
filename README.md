# MeuKM

Aplicativo PWA para controle de combustível, manutenção e outras despesas de veículos.

## Funcionalidades desta versão

- vários veículos;
- abastecimentos com cálculo automático de litros e valor;
- manutenções com lembretes por data e quilometragem;
- despesas gerais;
- histórico com filtros, edição e exclusão;
- relatórios de gastos, consumo e custo por quilômetro;
- tema claro e escuro;
- backup por arquivo JSON;
- armazenamento local e funcionamento offline.

## Abrir localmente

Sirva esta pasta por HTTP e abra o arquivo `index.html` pelo endereço do servidor. O armazenamento e o modo offline dependem de um contexto HTTP ou HTTPS.

## Publicação

O projeto inclui um fluxo do GitHub Actions em `.github/workflows/pages.yml`. Cada atualização enviada para a branch `main` publica automaticamente o aplicativo no GitHub Pages.
