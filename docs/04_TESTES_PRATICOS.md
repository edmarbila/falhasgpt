# Conferência antes de cadastrar o acervo definitivo

Use registros claramente identificados como teste. Faça a conferência em desktop e no celular pela URL HTTPS. Para conferir largura, também é possível usar o modo responsivo do navegador em 320, 390, 768 e 1440 pixels.

## Acesso

1. Abra a URL em janela anônima. Se configurou Cloudflare Access, a barreira da Cloudflare deve aparecer antes do site.
2. Com conexão central configurada, o Falhas GPT deve abrir em login/cadastro, sem pedir URL/chave.
3. Entre como administrador: deve haver **Administração**.
4. Tente cadastrar um RE não liberado: o cadastro deve ser recusado.
5. Libere um RE de teste, cadastre o operador e confirme o e-mail. O operador deve acessar o acervo, sem botões administrativos.
6. Revogue esse RE enquanto o operador está logado. A próxima chamada protegida deve ser recusada; a interface revalida a sessão também ao retomar a aba e periodicamente.
7. Não teste só ocultação dos botões: o SQL de validação deve confirmar a ausência de privilégios administrativos para `anon` e de escrita direta do operador na liberação de RE.

## Procedimentos e busca

1. Crie um registro com título **Guia geral de teste**. No texto completo, coloque **pressostato auxiliar**, sem essa expressão no título, palavras-chave ou resumo. Complete os requisitos e disponibilize.
2. Pesquise `pressostato auxiliar` e depois `presostato auxliar`. Deve encontrar o registro pelo conteúdo e mostrar **Ver trecho encontrado**.
3. Crie outro registro cujo título seja exatamente **Pressostato auxiliar**. Na consulta exata, o título deve ficar acima da correspondência só no conteúdo.
4. Teste resumo, aliases e palavras-chave, além de uma consulta sem correspondência. Verifique a relevância em ordem decrescente.
5. Edite o conteúdo e remova a expressão exclusiva. Ela deve deixar de recuperar aquele documento após salvar e atualizar os resultados.
6. Abra resumo, procedimento completo, todos os procedimentos e restabelecimentos. Confira fonte e revisão.
7. Exclua o registro de teste. Deve sair do acervo, pesquisa e relações. O histórico é preservado; o identificador não é reutilizado.

## Tópicos, Excel e PDF

- Durante uma edição, crie um tópico relacionado. Os campos já digitados devem permanecer. Salve o procedimento para confirmar o vínculo; complete o novo tópico, que nasce como rascunho.
- Importe uma planilha de teste com nomes, outros números e REs válidos. A prévia deve mostrar somente REs reconhecidos e sem duplicatas. Um RE revogado não pode ser reativado só pela importação.
- Importe um PDF textual. Confira a extração, a ordem dos passos e os campos obrigatórios antes de disponibilizar. Abra o anexo depois como operador autorizado.
- Use um PDF digitalizado para observar a limitação: não há OCR embutido. Texto vazio precisa ser transcrito ou tratado antes de publicar.

## CharleIA e celular

- No primeiro acesso da sessão, deve haver saudação e balão; após a reação, o movimento repetitivo termina.
- Uma consulta sem resultados provoca reação triste breve, seguida de pose estática.
- Nova consulta provoca uma fala de retorno; não repete a apresentação inicial.
- Movimentos ociosos são espaçados, pausam quando a aba está oculta e respeitam a preferência de movimento reduzido.
- No celular, confira menu, teclado, leitura dos textos completos, botão de excluir, formulários, balões e ausência de rolagem horizontal.

## O que foi validado neste pacote

O instalador completo foi executado em banco PostgreSQL de teste via PGlite, incluindo UUID de administrador diferente, RE, prioridade, conteúdo, bloqueio de reinstalação sobre acervo e atualização preservando registros. A migração corrigida reproduz e resolve o erro 42501 em conexão nova sem superusuário.

O navegador automatizado percorreu login, cadastro, RE/Excel, PDF, administração, busca, exclusão, animações e larguras de celular/desktop. A distribuição gerada foi servida em raiz e em `/falhas-gpt/`, com o SQL real por trás de transporte Auth/Storage simulado.

Isso não é um deploy real no seu GitHub/Cloudflare nem uma conexão com o seu Supabase. SMTP, contas reais, políticas do provedor, domínio, volume real de documentos e desempenho precisam da validação prática acima. Os arquivos `.cmd` são auxiliares Windows revisados; não foram executados em Windows neste ambiente.
