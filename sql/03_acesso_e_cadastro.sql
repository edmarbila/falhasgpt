-- EXEMPLOS DE ADMINISTRAÇÃO. Execute somente o bloco desejado no SQL Editor.
-- O script abaixo é seguro para leitura: as escritas são exemplos comentados.

-- 1. Localize seu usuário JÁ EXISTENTE no Authentication do MESMO projeto.
SELECT id,email FROM auth.users ORDER BY created_at DESC LIMIT 30;

-- 2. Copie o UUID correto para autorizar somente esse usuário.
-- INSERT INTO falhas_gpt.acessos(usuario_id)
-- VALUES ('COLE-AQUI-O-UUID-DO-USUARIO'::uuid) ON CONFLICT DO NOTHING;

-- 3. Cadastro de um procedimento oficial (preencha todo o conteúdo antes de executar).
-- INSERT INTO falhas_gpt.procedimentos
-- (codigo,topico,categoria,tipo,serie,resumo,procedimento_completo,aliases,palavras_chave,fonte,revisao,publicado)
-- VALUES (
--   'SEU-CODIGO-UNICO','Título oficial','Portas','procedimento','Série aplicável',
--   'Resumo fiel ao documento aprovado','Texto integral aprovado',
--   ARRAY['termo alternativo','outro nome conhecido'],ARRAY['palavra-chave'],
--   'Identificação do manual/documento','Revisão vigente',true
-- );

-- 4. Adicione uma equivalência de busca. A reindexação é automática.
-- INSERT INTO falhas_gpt.sinonimos(termo,equivalente)
-- VALUES ('expressao alternativa','expressao padrao')
-- ON CONFLICT (termo) DO UPDATE SET equivalente=EXCLUDED.equivalente;
-- Use termos normalizados: minúsculas, sem acentos ou pontuação. Não trate ações opostas como sinônimos.

-- 5. Edite aliases sem perder os atuais (substitua o código e o novo termo).
-- UPDATE falhas_gpt.procedimentos
-- SET aliases=array_append(aliases,'novo nome para a mesma ocorrência')
-- WHERE codigo='SEU-CODIGO-UNICO' AND NOT 'novo nome para a mesma ocorrência'=ANY(aliases);

-- 6. Cadastre relações explícitas, que ficam acima das relações automáticas.
-- UPDATE falhas_gpt.procedimentos SET relacionados=ARRAY[
--   (SELECT id FROM falhas_gpt.procedimentos WHERE codigo='CODIGO-RELACIONADO')
-- ] WHERE codigo='SEU-CODIGO-UNICO';

-- 7. Oculte os exemplos após cadastrar o conteúdo oficial.
-- UPDATE falhas_gpt.procedimentos SET publicado=false WHERE exemplo;

-- 8. Busca com limite e relevância mínima configuráveis.
SELECT topico,relevancia,origem_match,termo_encontrado FROM public.buscar_fgpt_v3('porta não abre',10,25);

-- 9. Revogação de acesso, se necessária. Não apaga o usuário Supabase.
-- DELETE FROM falhas_gpt.acessos WHERE usuario_id='UUID-DO-USUARIO'::uuid;
