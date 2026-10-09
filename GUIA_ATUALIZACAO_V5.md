> Referência histórica. Para a distribuição 5.1 e implantação em Pages, siga o README principal e sql/README.md. Os caminhos e pacotes citados abaixo se referem às entregas anteriores.

# Falhas GPT V5 — conexão, animação e pesquisa no conteúdo

URL privada: https://falhas-gpt-charleia.edmarbila.chatgpt.site

## O que mudou

- A CharleIA reage uma única vez por evento, durante cerca de 2,2 segundos, e volta a uma pose tranquila. Em repouso, pequenos movimentos acontecem a intervalos variáveis de 28–45 segundos, apenas com a página visível e sem digitar. O modo de movimento reduzido desativa as animações.
- Há um balão com frases variadas de boas-vindas, busca, resultado, frustração e sucesso. A saudação inicial ocorre uma vez por sessão da aba. Em Nova consulta ou Fazer outra pergunta, ela recebe a pessoa de volta sem repetir a apresentação. A tristeza fica em uma pose estática até a próxima interação.
- Administradores podem excluir procedimentos pela lista ou pela edição. A exclusão tira o registro do acervo, pesquisa e relações, mantendo o histórico e o identificador. É exclusão lógica, sem apagar PDFs e registros de auditoria. Operadores perdem o acesso aos anexos; links já emitidos podem durar até os 60 segundos previstos.
- O motor indexa título, aliases, palavras-chave, contexto, resumo e texto completo. O conteúdo de PDFs entra na busca quando o texto extraído é salvo no procedimento. Títulos e aliases exatos têm prioridade; resumo e conteúdo recebem pesos menores. O resultado informa o campo e oferece Ver trecho encontrado. São correspondências textuais aproximadas, não compreensão semântica por IA.
- Dentro da edição é possível pesquisar tópicos existentes, inclusive rascunhos, e criar um novo tópico sem perder os campos preenchidos.

## 1. Atualizar o SQL

**Correção de 08/10/2026:** se o SQL 04 anterior falhou com `permission denied to set parameter "pg_trgm.similarity_threshold"`, substitua-o pela cópia corrigida e execute o arquivo inteiro novamente; depois execute o SQL 05 corrigido. Não precisa reinstalar o site nem a V4. A versão corrigida usa comparações explícitas, sem definir parâmetros `pg_trgm`. O nome da RPC e os pesos da busca continuam iguais. Veja também `sql/v5/LEIA-ME_CORRECAO_SQL.md`.

Se você já concluiu a instalação V4, **execute somente estes dois arquivos**, nesta ordem, no SQL Editor do mesmo projeto:

1. `SQL/04_ATUALIZAR_V4_PARA_V5.sql` — cole e execute inteiro. É transacional, reaplicável e reindexa também os textos já existentes.
2. `SQL/05_VALIDAR_V5.sql` — somente leitura. Deve aparecer a versão 5; com documentos preenchidos, as origens `resumo` e `conteudo` devem ter trechos. `anon_pode_excluir_deve_ser_false` deve ser `false` e `rpc_disponivel_deve_ser_true` deve ser `true`.

Faça backup antes de alterar o banco. Se houver erro, pare e envie a mensagem completa. Se a sessão indicar transação abortada, execute `ROLLBACK;`. Não apague tabelas nem políticas para contornar o erro. O banco real não foi acessado nesta entrega; não é possível garantir compatibilidade com alterações locais desconhecidas.

Se a V4 ainda não foi concluída, siga primeiro os quatro arquivos `00`, `01`, `02` e `03` da pasta `SQL`, conforme o guia V4 em `SITE/GUIA_ATUALIZACAO_V4.md`; depois aplique `04` e `05`. **Não reaplique os instaladores V3/V4 depois da V5**, pois substituem funções e permissões da versão nova. A RPC de busca continua se chamando `buscar_fgpt_v3` para manter compatibilidade.

Em acervos grandes, a reindexação pode demorar. Se o SQL Editor apresentar timeout, preserve o banco e envie o erro para preparar a atualização em lotes, sem executar fragmentos aleatórios.

## 2. Preservar a conexão que você já preencheu

A configuração deve estar em `public/project-config.js` dentro da pasta do site:

```js
export const PUBLIC_PROJECT = {
  url: 'https://SEU-PROJETO.supabase.co',
  key: 'SUA_CHAVE_PUBLICA_PUBLISHABLE_OU_ANON'
};
```

Mantenha os seus valores reais. Não coloque a configuração no `index.html`, no SQL ou em um arquivo `.env`: este site estático lê `public/project-config.js`. Use somente chave pública, nunca `service_role`, `sb_secret_` ou senha.

Nesta versão, a configuração desse arquivo tem prioridade sobre configurações antigas salvas no navegador. Com ela preenchida, o usuário abre direto o login/cadastro; o botão Configurar conexão não aparece na tela inicial. A configuração permanece acessível ao administrador pelo menu, com URL/chave do arquivo protegidas contra edição acidental. Se você configurou apenas pelo formulário, os valores continuam locais àquele navegador.

**Atualizar o pacote sem perder as chaves:** extraia este ZIP em uma pasta nova e execute `ATUALIZAR_SITE.cmd`. Informe a pasta anterior que contém `public` e `package.json`. O atualizador faz backup dos arquivos substituídos e preserva o seu `public/project-config.js`. Ele não instala SQL e não faz deploy. Feche o servidor de teste antes de atualizar. O script foi revisado; não foi executado em um Windows real neste ambiente.

Alternativa manual: copie sua configuração atual para um lugar seguro, substitua os arquivos do site pelos de `SITE` e restaure `public/project-config.js`. Não sobrescreva esse arquivo com a versão `null` do pacote.

**Arquivo local e site hospedado são cópias diferentes.** Editar no PC não atualiza a URL privada. Para configurar a hospedagem também, envie o arquivo `project-config.js` preenchido ou seu bloco com URL/chave pública. Nenhuma credencial real foi recebida até agora; a cópia hospedada ainda não tem a conexão central preenchida. A audiência da hospedagem continua restrita ao proprietário.

## 3. Testar no Windows

O site usa módulos JavaScript e PDF.js. Abrir `index.html` com duplo clique gera uma URL `file://`, que não serve para esse teste. Agora essa abertura mostra uma orientação em vez de uma tela vazia. Referência: [módulos JavaScript — MDN](https://developer.mozilla.org/pt-BR/docs/Web/JavaScript/Guide/Modules).

1. Tenha o Node.js LTS instalado. Não precisa rodar `npm install` para apenas abrir este site estático.
2. Na pasta atualizada do site, dê duplo clique em `INICIAR_TESTE_LOCAL.cmd`.
3. Abra `http://localhost:4173` se o navegador não abrir automaticamente.
4. Mantenha a janela do servidor aberta durante o teste. `Ctrl+C` encerra.

Pelo PowerShell, ajuste o caminho à sua pasta real:

```powershell
cd "D:\Apps\FalhasGPT\SITE"
node server.mjs --open
```

O servidor usa somente o próprio computador (`127.0.0.1`), serve os módulos e o worker de PDF com o tipo correto e desativa cache durante o teste. Se a porta 4173 estiver ocupada, feche o servidor anterior. Depois de atualizar os arquivos, use `Ctrl+F5` no navegador.

Para testar confirmação de e-mail local, adicione `http://localhost:4173/` às URLs de retorno permitidas do Auth no Supabase, preservando a URL hospedada e as configurações dos demais aplicativos. Para login de uma conta já confirmada, não é necessário recadastrar a pessoa.

## 4. Como funcionam os tópicos relacionados

Um tópico é um registro de procedimento ou restabelecimento. O título do registro é o nome do tópico. Não é uma lista fixa limitada a portas: os exemplos anteriores eram sobre portas. Agora os atalhos de sugestões na tela inicial também usam os títulos do acervo disponível.

As sugestões automáticas consideram categoria, proximidade dos títulos e palavras-chave em comum. Relações selecionadas pelo administrador aparecem primeiro. Você não precisa escolher manualmente cada relação para que existam sugestões.

Na seção Tópicos relacionados da edição:

1. Use Buscar tópico existente para localizar outro assunto. A lista retorna até 50 correspondências, além dos já selecionados.
2. Se não existir, preencha Título do novo tópico e Tipo e clique em Criar tópico e selecionar.
3. O novo tópico é salvo imediatamente como rascunho, com categoria/série da edição atual. Se já houver um registro com o mesmo título normalizado e tipo, ele é selecionado sem duplicar.
4. Salve o procedimento atual para confirmar seu vínculo com o novo tópico.
5. Depois, abra o novo rascunho no painel e complete resumo, texto, fonte, revisão e aplicabilidade antes de disponibilizá-lo. Rascunhos não são mostrados aos operadores.

Se cancelar a edição principal, o novo rascunho continua existindo, mas o vínculo ainda não salvo não é aplicado. Você pode completá-lo ou excluí-lo. Há limite de 30 relações por registro.

## 5. Conferência rápida

- Abra o site com `project-config.js` preenchido: deve ir ao login sem pedir as chaves.
- Espere a saudação terminar: a ação deve parar. Faça uma consulta sem resultados; depois escolha Nova consulta: deve aparecer uma fala de retorno com expressão feliz, sem nova apresentação.
- Crie um procedimento de teste com um termo exclusivo apenas no texto completo. Pesquise esse termo e uma pequena variação de escrita: o resultado deve trazer o trecho. Um título exato equivalente deve ficar acima do conteúdo.
- Edite o texto e salve: os termos novos entram na busca e os removidos deixam de ser indexados.
- Crie um tópico durante outra edição: os campos anteriores devem permanecer preenchidos.
- Exclua um registro de teste: ele deve sumir da lista, pesquisa e relações, sem reutilizar o identificador.

Os testes automatizados cobrem essas regras em PostgreSQL local via PGlite e navegador em desktop/celular. O transporte de autenticação e armazenamento é simulado. O teste final do seu Supabase depende de aplicar os SQLs e usar suas contas reais.
