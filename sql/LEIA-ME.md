> Referência histórica. Para a distribuição 5.1 e implantação em Pages, siga o README principal e sql/README.md. Os caminhos e pacotes citados abaixo se referem às entregas anteriores.

# Falhas GPT — motor de busca V3

Site privado: https://falhas-gpt-charleia.edmarbila.chatgpt.site

O pacote instala um motor de busca para procedimentos e restabelecimentos no Supabase. Os resultados vêm do mais próximo para o menos próximo, com pontuação e motivo da correspondência. A instalação cria objetos V3 separados e preserva a função `buscar_fgpt_v2` e as tabelas antigas.

## Onde colar e em qual ordem

1. Abra **seu projeto Supabase → SQL Editor → New query**. Cole todo o conteúdo de `01_instalar_motor_busca.sql` e execute com **Run**. Requer PostgreSQL 15 ou superior e uma conta administradora do banco. A mensagem final confirma a instalação. Esse arquivo não cadastra procedimentos nem autoriza usuários automaticamente.
2. Para experimentar a busca antes de importar seu acervo, execute `02_exemplos_para_validar.sql`. É opcional: insere quatro exemplos identificados como demonstração, sem instruções operacionais. Pode ser reaplicado sem duplicá-los.
3. Abra `03_acesso_e_cadastro.sql`. Execute a consulta do item 1 para localizar o UUID de um usuário existente em **Authentication → Users** do mesmo projeto. No item 2, substitua o UUID indicado, remova os `--` dessas duas linhas e execute somente o bloco `INSERT`. Isso autoriza esse usuário a consultar o acervo.
4. No site, clique em **Conectar acervo Supabase**. Informe a URL do projeto, a chave pública `anon` ou `sb_publishable_...`, o e-mail e a senha do usuário autorizado. Clique em **Testar e conectar**. O usuário de Authentication pertence ao seu aplicativo; não é necessariamente a conta usada para entrar no painel Supabase ou no ChatGPT.
5. Para usar o acervo antigo, execute `04_diagnostico_base_existente.sql` e forneça o resultado para preparar a importação com os nomes reais das tabelas e colunas. Esse arquivo é somente leitura. O instalador não adivinha nem copia dados antigos.

Os demais blocos de `03` são modelos comentados de cadastro, sinônimos, relações e revogação de acesso. Executar o arquivo inteiro como está não autoriza ninguém nem cadastra um procedimento. Edite e execute apenas o bloco necessário.

## Configuração do site

| Campo | Valor V3 |
|---|---|
| Tabela ou view | `vw_fgpt_acervo_v3` |
| Função RPC | `buscar_fgpt_v3` |
| Parâmetro do texto | `p_busca` |
| Parâmetro do limite | `p_limite` |
| Coluna para ordenar o acervo | `id` |

Esses valores já estão preenchidos para conexões novas. Se o navegador mantém uma configuração V2, abra **Gerenciar conexão → Função de busca e parâmetros → Usar configuração do motor V3**, depois teste e conecte. Não adicione o schema interno `falhas_gpt` à lista de schemas expostos na API: o site usa a view e as RPCs em `public`.

A chave pública e os nomes da configuração ficam neste navegador. A senha não é salva pelo aplicativo. Os tokens da sessão ficam em `sessionStorage`, são renovados quando necessário e são removidos ao desconectar. Não use `service_role` ou chave `secret` no site. O acesso privado ao site e o login no Supabase são controles separados.

## Como a prioridade funciona

| Correspondência | Prioridade típica, antes dos ajustes |
|---|---:|
| Título exato, desconsiderando acentos e caixa | 100 |
| Nome alternativo exato (alias) | 98 |
| Expressão equivalente no título ou alias | 96 / 95 |
| Mesmos termos úteis em outra ordem | 93 |
| Todos os termos encontrados | 86–90 |
| Palavras próximas e erros de digitação | Até 88 |
| Correspondência parcial | Até 68 |

O cálculo combina texto normalizado, equivalências cadastradas, trigramas, distância de edição e cobertura dos termos. Palavras-chave isoladas e contexto têm limites menores. Ações opostas como “abre” e “fecha” e diferenças de negação reduzem a pontuação. O resultado usa a melhor correspondência de cada procedimento, sem repeti-lo; empates são resolvidos por título e ID. A pontuação de 0 a 100 mede proximidade textual, não probabilidade ou validade operacional.

A busca considera título, aliases, palavras-chave, categoria e série. Resumo e procedimento completo são devolvidos para consulta, mas não usados para elevar a relevância por ocorrências incidentais em textos longos. As equivalências são explícitas e editáveis, sem serviço externo de IA ou embeddings. Para vocabulário específico do seu acervo, cadastre os aliases e sinônimos correspondentes.

A ordem sempre é `relevancia DESC`. Padrões: 10 resultados, pontuação mínima 25. Limites: 50 resultados por chamada e 200 caracteres de consulta. Texto vazio ou sem termos úteis retorna lista vazia. Para explorar mais aproximações, diminua `p_minimo`; para exigir mais precisão, aumente-o.

```sql
SELECT topico, relevancia, origem_match, termo_encontrado
FROM public.buscar_fgpt_v3(
  p_busca => 'porta nao fexa',
  p_limite => 10,
  p_minimo => 25
);
```

Com os quatro exemplos do arquivo 02, os testes retornaram:

| Consulta | Primeiro resultado | Pontuação |
|---|---|---:|
| porta não abre | Porta não abre | 100,00 |
| prota nao abre | Porta não abre | 76,53 |
| porta nao fexa | Porta não fecha | 77,21 |
| isolamneto de porta | Isolamento de porta | 80,67 |
| restabelecer portas | Restabelecimento de portas | 95,00 |

Para “porta não abre”, o tópico “Porta não fecha” aparece abaixo, com 31,57. Os valores dependem dos títulos, aliases e sinônimos cadastrados.

## Tópicos relacionados e manutenção

`public.relacionados_fgpt_v3(p_id uuid, p_limite integer DEFAULT 5)` prioriza as relações cadastradas em `relacionados`; depois considera proximidade do título, categoria e palavras-chave. Não retorna o próprio registro nem rascunhos. O site apresenta essas relações no painel do procedimento.

Cadastre o conteúdo real em `falhas_gpt.procedimentos`, usando os modelos do arquivo 03. Use `tipo='restabelecimento'` para a seção correspondente. Registros novos começam com `publicado=false`. Para publicar um registro oficial, preencha título, resumo e texto completo; registre também fonte, revisão e série para a consulta. Alterações nos títulos, aliases e palavras-chave atualizam os índices automaticamente. Mudanças no dicionário de sinônimos reindexam o acervo.

Após importar o conteúdo oficial, oculte os exemplos pelo comando indicado no arquivo 03. Reaplicar o instalador preserva os registros e reaplica as funções e permissões V3. Ele não remove objetos antigos nem altera seu conteúdo operacional.

## Acesso e validação

O banco usa RLS: apenas usuários autenticados incluídos em `falhas_gpt.acessos` consultam registros publicados. Os usuários de consulta não recebem permissão para editar o acervo ou autorizar outras pessoas. O administrador gerencia os dados pelo SQL Editor. A view usa `security_invoker`, e as funções não elevam privilégios.

Validação executada em PostgreSQL local via PGlite com `pg_trgm` e `fuzzystrmatch`: instalação, reaplicação, preservação da função antiga, ranking, limites, reindexação de sinônimos, rascunhos ocultos e bloqueio de leituras anônimas/escritas não autorizadas. O site foi verificado em navegador nos tamanhos de celular e desktop, com backend simulado para login, sessão e respostas da API.

**Não foi executado no seu projeto Supabase:** faltam URL, chave pública, esquema e acervo reais. A conexão real e a importação dependem desses dados e da instalação no projeto correto. Não foi realizado teste de carga com seu acervo. Os índices de texto e trigramas estão incluídos; a comparação aproximada de palavras pode examinar muitos termos e deve ser medida com o volume real. O site carrega o catálogo em páginas e informa erro se exceder o limite de 10 mil registros, sem apresentar uma lista incompleta como completa.

Se aparecer “função não encontrada”, confirme os campos V3 e a execução completa do arquivo 01. Se aparecer “usuário não autorizado”, verifique o UUID no arquivo 03. Acervo vazio significa que não há registros publicados acessíveis; instale os exemplos opcionais ou importe os oficiais. Falhas de conexão são exibidas sem substituir silenciosamente o acervo pelos exemplos.

Referências técnicas: [pg_trgm](https://www.postgresql.org/docs/current/pgtrgm.html), [fuzzystrmatch](https://www.postgresql.org/docs/current/fuzzystrmatch.html), [RLS no Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security).
