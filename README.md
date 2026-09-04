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
- cadastro e login online com senha gerenciada pelo Supabase Auth;
- sincronização automática entre celular e computador, mantendo o uso offline;
- relatórios com gráficos exportáveis em PNG e PDF;
- cálculo de consumo real em km/L a partir de tanques completos;
- previsão do próximo abastecimento com base nos intervalos anteriores;
- backup por arquivo JSON;
- exclusão completa de dados com confirmação digitada;
- armazenamento local e funcionamento offline;
- base Flutter em desenvolvimento para Android e Windows.

> A sincronização usa uma conta MeuKM. Cada usuário acessa somente seus próprios dados por meio de políticas de segurança no banco. O arquivo de backup não inclui senha nem sessão de acesso.

## Abrir localmente

Sirva esta pasta por HTTP e abra o arquivo `index.html` pelo endereço do servidor. O armazenamento e o modo offline dependem de um contexto HTTP ou HTTPS.

## Publicação

O projeto inclui um fluxo do GitHub Actions em `.github/workflows/pages.yml`. Cada atualização enviada para a branch `main` publica automaticamente o aplicativo no GitHub Pages.
