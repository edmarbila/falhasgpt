> Referência histórica. Para a distribuição 5.1 e implantação em Pages, siga o README principal e sql/README.md. Os caminhos e pacotes citados abaixo se referem às entregas anteriores.

# Falhas GPT V4 — instalação inicial

> Para a atualização atual, siga primeiro `GUIA_ATUALIZACAO_V5.md`. Após instalar a V4, aplique os arquivos 04 e 05 da V5.

Site privado: https://falhas-gpt-charleia.edmarbila.chatgpt.site

Este pacote reúne os SQLs completos, o site, as funções administrativas, os leitores de Excel/PDF e as animações da CharleIA. O backend real ainda não foi conectado nem alterado nesta entrega: faltam a URL e a chave pública do projeto Supabase. O instalador foi validado em PostgreSQL local com dados de teste e reaplicação, mas o esquema atual do seu projeto não foi inspecionado.

## 1. Antes de executar

1. Extraia o ZIP. No Windows, pode usar `D:\Apps\FalhasGPT\V4`. A pasta `SQL` contém os quatro arquivos que você executará; `SITE` contém o código completo.
2. Abra o **projeto Supabase existente correto**. Faça backup/exportação do acervo e das configurações atuais antes da atualização. Se tiver um ambiente de homologação, aplique nele primeiro.
3. Em **Authentication → Users**, confirme que existe o usuário `35eadffb-84a8-499c-8a24-bdb0231ef2de`. Ele será o administrador. O UUID não é uma senha nem um e-mail de login. Use o e-mail e a senha já associados a essa conta.
4. O instalador requer PostgreSQL 15 ou superior. Não exige criar um novo projeto, apagar tabelas, recriar contas nem executar funções Edge.

O erro exato do SQL 03 anterior não foi disponibilizado. Portanto, este pacote não presume a causa daquele erro. A atualização V4 contém sua própria instalação completa e sua própria validação; não depende de executar o antigo SQL 03.

## 2. Aplicar os quatro arquivos, nesta ordem

No **SQL Editor**, abra uma consulta para cada arquivo, cole **todo o conteúdo** e execute. Não selecione apenas trechos do instalador. Só avance se o arquivo anterior terminar sem erro.

| Ordem | Arquivo na pasta SQL | O que faz / resultado esperado |
| --- | --- | --- |
| 1 | `00_DIAGNOSTICO.sql` | Somente leitura: versão do PostgreSQL, usuário administrador, colunas existentes, funções e triggers. A consulta do administrador deve retornar o UUID informado. |
| 2 | `01_INSTALAR_ATUALIZACAO_V4.sql` | Instala a base de busca V3 junto com toda a V4, em uma transação. Cria administração, autorização por RE, perfis, auditoria, cadastro de procedimentos e permissões. |
| 3 | `02_PDFS_PRIVADOS.sql` | Cria/configura o bucket privado de PDFs, suas políticas e a função de vincular anexos aos procedimentos. |
| 4 | `03_VALIDAR_INSTALACAO.sql` | Somente leitura: mostra versão 4, administrador ativo, contagens, trigger, bucket e permissões. |

No resultado do arquivo 03, confira:

- `falhas_gpt.migracoes` contém a versão `4`.
- O administrador informado está com `ativo = true`.
- Existe o trigger `fgpt_validar_cadastro_v4`, habilitado (`tgenabled = O`).
- O bucket `falhas-gpt-procedimentos` está com `public = false`, limite `20971520` bytes e tipo `application/pdf`.
- `anon_pode_liberar_deve_ser_false` e `operador_pode_gravar_re_deve_ser_false` são ambos `false`.
- Zero REs e zero procedimentos são normais em uma instalação vazia. O pacote não libera REs fictícios.

**Se aparecer um erro:** pare, copie a mensagem completa e o arquivo em execução. Se a sessão indicar transação abortada, execute `ROLLBACK;` antes de tentar novamente. Não apague tabelas ou políticas para contornar o erro. O arquivo 01 é atômico: uma falha antes do `COMMIT` impede que ele deixe metade da atualização aplicada. O arquivo 02 também usa transação; sua falha não desfaz um arquivo 01 já concluído.

Os instaladores podem ser reaplicados e preservam os dados conhecidos do schema `falhas_gpt`, códigos existentes e funções V2. **Não execute novamente os instaladores antigos depois da V4**, pois eles podem restaurar permissões anteriores. Não execute o fragmento `SITE/sql/v4/admin_re_migration.sql` sozinho; ele serve apenas para gerar o instalador completo.

Dados em tabelas antigas com nomes/colunas diferentes não são migrados automaticamente. Se o acervo atual estiver fora de `falhas_gpt.procedimentos`, envie o resultado do diagnóstico e a estrutura dessas tabelas para preparar uma importação compatível. Não há exclusão automática desse acervo.

## 3. Configurar autenticação e conectar o site

No Supabase, confirme que o login por e-mail/senha e o cadastro de novos usuários estão habilitados conforme a política do seu projeto. Mantenha a confirmação de e-mail se ela já é exigida. Se o projeto atende outros aplicativos, preserve as configurações deles.

Em **Authentication → URL Configuration**, autorize o retorno para `https://falhas-gpt-charleia.edmarbila.chatgpt.site/`. Se o projeto for dedicado ao Falhas GPT, essa também pode ser sua Site URL. Em projeto compartilhado, mantenha a Site URL existente e adicione este endereço às URLs permitidas. Não use curingas amplos. O cadastro do aplicativo informa explicitamente esse endereço de retorno.

Obtenha a **URL do projeto** e uma **chave pública publishable** (ou `anon` legada). Não use `service_role`, `sb_secret_`, senha do banco nem token pessoal. A chave pública identifica o aplicativo; a sessão do usuário e as políticas do banco controlam os dados.

Para validar no seu navegador:

1. Abra a URL privada e clique em **Configurar conexão**.
2. Informe a URL e a chave pública. Use a configuração do motor V3: tabela/view `vw_fgpt_acervo_v3`, função `buscar_fgpt_v3`, parâmetro de pesquisa `p_busca`, limite `p_limite` e ordenação `id`.
3. Entre com o e-mail e a senha do administrador designado. Conclua o teste de conexão. A senha não é salva pelo aplicativo.
4. Confira a opção **Administração** no menu. No celular, abra o menu lateral.

Essa configuração pelo formulário vale apenas para aquele navegador. Para deixar a conexão pronta em **todos os dispositivos**, envie a URL do projeto e a chave pública para que sejam incorporadas ao site, ou edite `SITE/public/project-config.js` assim e atualize a mesma hospedagem privada:

```js
export const PUBLIC_PROJECT = {
  url: 'https://SEU-PROJETO.supabase.co',
  key: 'sb_publishable_SUA_CHAVE_PUBLICA'
};
```

Não use os exemplos acima literalmente. A configuração atual desse arquivo é `null`; ainda precisa dos dados reais. Na interface V5, a configuração desse arquivo tem prioridade sobre valores antigos salvos no navegador. Se necessário, remova a conexão local pelo próprio aplicativo e configure novamente.

Referências oficiais consultadas em 08/10/2026: [chaves de API](https://supabase.com/docs/guides/getting-started/api-keys), [URLs de retorno](https://supabase.com/docs/guides/auth/redirect-urls) e [configuração de autenticação](https://supabase.com/docs/guides/auth/general-configuration).

## 4. Liberar, importar e revogar REs

Em **Administração → Liberação de RE**:

- **Individual:** informe `59-00000` e clique em **Liberar RE**. O prefixo deve ser `59`, seguido de exatamente cinco dígitos. A forma numérica de sete dígitos é normalizada.
- **Planilha:** selecione `.xlsx`, `.xls` ou `.csv`. O leitor procura REs em todas as abas, ignora nomes e demais células sem RE e elimina duplicados. Confira a prévia antes de confirmar. Apenas a lista de REs é enviada ao backend; a planilha original e suas outras colunas não são cadastradas.
- **Limites:** 10 MB por planilha, 30 abas, 50 mil linhas por aba, 200 mil células e 5 mil REs por lote. Divida arquivos maiores. Todo valor que corresponda ao formato de RE pode ser identificado; a prévia permite conferir eventuais números ambíguos.
- **Revogar:** clique em **Excluir liberação** e confirme. O banco bloqueia novas consultas imediatamente, inclusive com sessão ainda válida. A tela revalida a autorização em até 60 segundos ou ao retornar à aba. Arquivos já baixados não podem ser recolhidos; um link de PDF já emitido pode funcionar por até 60 segundos.
- **Reativar:** é uma ação individual explícita. Reimportar uma planilha nunca reativa REs revogados.

A exclusão é uma revogação lógica: preserva a conta Auth, o vínculo do RE e a auditoria. Não apaga o funcionário ou o histórico. Um RE vinculado não pode ser reclamado por outro usuário. Se houver troca legítima de titular, a alteração deve ser tratada administrativamente após verificar a identidade; não há botão automático para transferir o vínculo.

O operador usa **Cadastrar** na tela inicial, informa nome, RE, e-mail e senha. O banco valida o RE liberado e ainda não utilizado, e cria o vínculo na mesma transação do cadastro. Se houver confirmação de e-mail, ele deve confirmá-lo antes de entrar. Contas já existentes podem entrar e vincular um RE disponível pela tela **Liberar acesso**.

O administrador designado não depende de RE. Operadores antes autorizados apenas pela lista V3 precisam vincular RE após esta atualização. A validação por trigger é específica para cadastros com `app = falhas_gpt`; cadastros de outros aplicativos do mesmo projeto continuam possíveis, mas não recebem acesso ao acervo Falhas GPT sem perfil e RE válido. Não existe consulta pública da lista de REs.

## 5. Cadastrar procedimentos e restabelecimentos

Em **Administração → Procedimentos → Novo procedimento**:

1. Escolha o tipo: procedimento ou restabelecimento.
2. Preencha título e os demais campos. Para disponibilizar aos operadores, são obrigatórios categoria, série/aplicabilidade, resumo, texto completo, fonte e revisão.
3. Use **Número do documento de origem** para o número do manual/instrução oficial. Ele é separado do identificador automático.
4. Cadastre nomes alternativos e palavras-chave, um por linha (até 50 de cada, até 250 caracteres por item). Selecione até 30 tópicos relacionados existentes.
5. Deixe **Disponibilizar no acervo dos operadores** desmarcado para salvar rascunho. Para publicar no acervo autenticado, revise o documento e marque essa opção. Isso não muda a visibilidade da hospedagem.
6. Salve. O servidor atribui um identificador como `trafego-trens-falhasgptapp-01`, `-02` e assim por diante. Acima de 99, continua `-100`, sem truncar os dígitos. Editar não troca o código; códigos antigos são preservados. Sequências podem ter lacunas e nunca são reiniciadas ao importar.

O resumo admite até 6 mil caracteres; o texto completo, até 2 milhões. Conflitos de edição são detectados: se outra sessão salvou uma versão mais nova, recarregue o procedimento antes de reaplicar sua alteração.

A busca prioriza correspondências mais próximas e apresenta pontuação/motivo. Aliases e palavras-chave ajudam a localizar vocabulário usado na operação. Tópicos relacionados combinam relações explícitas e proximidade textual. O usuário abre primeiro o resumo e depois o texto completo. A correspondência textual não substitui a conferência de revisão, série e condições do documento aprovado.

## 6. Importar PDFs existentes

**Dentro de um procedimento:** use **Importar texto de um PDF**. O texto extraído preenche o conteúdo completo. Revise a ordem dos passos e preencha resumo, aplicabilidade, fonte e revisão. Confirme a caixa de revisão antes de salvar. O original é anexado ao registro.

**Importação em lote:** na lista administrativa, selecione até 20 PDFs. Confira a prévia e clique em **Criar rascunhos**. Cada arquivo cria um rascunho separado; nenhum é disponibilizado automaticamente aos operadores. Se um PDF contiver vários procedimentos, separe-os e revise cada registro.

Limites: 20 MB e 300 páginas por PDF. O leitor extrai texto selecionável; documentos digitalizados sem texto precisam de OCR externo ou preenchimento manual. Não há OCR automático neste pacote. Tabelas e colunas podem perder a ordem durante a extração, por isso a revisão é obrigatória. PDFs protegidos por senha precisam de uma cópia acessível.

Os originais ficam no bucket privado `falhas-gpt-procedimentos`. Operadores autorizados só podem abrir PDFs vinculados a registros disponíveis no acervo; rascunhos são administrativos. Os links de abertura expiram após 60 segundos. Se o upload falhar depois de salvar o registro, o site informa que o rascunho foi preservado; abra-o para anexar novamente, sem criar uma duplicata.

## 7. CharleIA animada

A cartela `public/assets/charleia-animada.png` contém 20 quadros: quatro quadros para cada um de cinco estados. `mascot.js` e `v4.css` controlam saudação, busca, tristeza quando não há resultado, alegria ao encontrar e comemoração quando o usuário confirma que foi atendido. É animação por quadros em CSS, já incluída no site, sem instalação adicional. A preferência do dispositivo por movimento reduzido é respeitada.

## 8. Validação e privacidade

Foram testados: ranking, correspondências próximas, permissões de operador/administrador, cadastro recusado/aceito por RE, duplicidade de RE, revogação com sessão ativa, importação de planilha, leitura de PDF, rascunhos, sequência de códigos, instalação repetida e políticas de arquivos. O teste de navegador cobriu larguras de 320, 390, 768 e 1440 pixels e os quadros da animação. Auth/Storage HTTP foram simulados; as funções SQL foram executadas em PostgreSQL local via PGlite. Isso não substitui um teste no seu Supabase após aplicar os arquivos.

Após conectar o projeto, faça um teste com um RE autorizado de teste, crie um rascunho, importe um PDF e valide o acesso como operador. Em seguida, revogue o RE e confirme o bloqueio. Use conteúdo fictício claramente identificado durante essa conferência.

**A hospedagem continua restrita ao proprietário.** O cadastro no aplicativo está implementado, mas outros funcionários só conseguirão visitar essa URL quando você autorizar a forma de compartilhamento. Nenhuma ampliação de audiência foi feita. Depois dessa autorização, a validação de RE e o login continuam obrigatórios para consultar o acervo.

## 9. Se algo não funcionar

| Sintoma | Próximo passo |
| --- | --- |
| Administrador ausente no arquivo 00 | Confira se abriu o projeto correto e se o UUID existe em Authentication → Users. Não substitua por um UUID aleatório. |
| SQL 01 ou 02 falhou | Pare e envie a mensagem completa. Não siga executando os arquivos seguintes nem remova objetos do banco. |
| “Instale a atualização SQL V4” | Confirme que executou o arquivo 01 completo no projeto da URL configurada. Aguarde a atualização do cache da API e tente novamente. |
| Login válido, sem Administração | Confirme a conta usada, o UUID e a linha ativa em `falhas_gpt.administradores`; saia e entre novamente. |
| Cadastro não concluído | Confira RE ativo/livre, confirmação de e-mail e regras Auth do projeto. O site não revela publicamente se um RE específico existe. |
| Operador sem acesso | Libere/vincule o RE no painel. A antiga autorização V3, sozinha, não libera operadores na V4. |
| Upload de PDF recusado | Confira arquivo 02, tamanho/tipo do PDF e sessão de administrador. Não torne o bucket público. |
| Acervo antigo não aparece | Verifique sua tabela de origem e o diagnóstico. É necessário mapear os campos antes de importar para a estrutura V4. |
| Confirmação de e-mail retorna ao endereço errado | Confira URL Configuration e template de e-mail no projeto; preserve as URLs de outros aplicativos. |

Não há reversão automática para políticas antigas: ela poderia reabrir acessos revogados. Em caso de incompatibilidade real, preserve os dados e prepare uma correção a partir do erro e do diagnóstico.
