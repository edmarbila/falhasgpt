-- OPCIONAL: quatro registros de demonstração. Nenhuma instrução operacional.
-- Reexecutável: não sobrescreve registros existentes com o mesmo código.
BEGIN;
INSERT INTO falhas_gpt.procedimentos(codigo,topico,categoria,tipo,resumo,procedimento_completo,aliases,palavras_chave,publicado,exemplo)
VALUES
('DEMO-PORTA-ABERTURA','Porta não abre','Portas','procedimento',
 'Exemplo de pesquisa sobre falha de abertura. O procedimento oficial deve ser cadastrado.',
 'DEMONSTRAÇÃO. Nenhuma ação operacional prescrita. Substitua este registro pelo documento aprovado.',
 ARRAY['falha de abertura da porta','porta não está abrindo','não consigo abrir a porta','porta travada na abertura'],ARRAY['porta','abertura'],true,true),
('DEMO-PORTA-FECHAMENTO','Porta não fecha','Portas','procedimento',
 'Exemplo de pesquisa sobre falha de fechamento. O procedimento oficial deve ser cadastrado.',
 'DEMONSTRAÇÃO. Nenhuma ação operacional prescrita. Substitua este registro pelo documento aprovado.',
 ARRAY['falha de fechamento da porta','porta não está fechando','não consigo fechar a porta','porta permanece aberta'],ARRAY['porta','fechamento'],true,true),
('DEMO-PORTA-ISOLAMENTO','Isolamento de porta','Portas','procedimento',
 'Exemplo de pesquisa por isolamento. O procedimento oficial deve ser cadastrado.',
 'DEMONSTRAÇÃO. Nenhuma sequência de isolamento foi fornecida. Cadastre o documento aprovado.',
 ARRAY['isolar porta','realizar o isolamento','isolamento da porta'],ARRAY['porta','isolamento'],true,true),
('DEMO-PORTA-RESTABELECIMENTO','Restabelecimento de portas','Portas','restabelecimento',
 'Exemplo de pesquisa por restabelecimento. O procedimento oficial deve ser cadastrado.',
 'DEMONSTRAÇÃO. Nenhuma sequência de restabelecimento foi fornecida. Cadastre o documento aprovado.',
 ARRAY['restabelecer porta','restabelecer as portas','restabelecimento da porta'],ARRAY['porta','restabelecimento'],true,true)
ON CONFLICT (codigo) DO NOTHING;
COMMIT;

-- Verifique a ordem. Relevância mede correspondência textual, não certeza operacional.
SELECT topico,relevancia,origem_match,termo_encontrado FROM public.buscar_fgpt_v3('porta não abre',10);
SELECT topico,relevancia,origem_match FROM public.buscar_fgpt_v3('prota nao abre',10);
SELECT topico,relevancia,origem_match FROM public.buscar_fgpt_v3('porta nao fexa',10);
SELECT topico,relevancia,origem_match FROM public.buscar_fgpt_v3('realizar o isolamento',10);
SELECT topico,relevancia,origem_match FROM public.buscar_fgpt_v3('portas',10);
SELECT * FROM public.relacionados_fgpt_v3((SELECT id FROM falhas_gpt.procedimentos WHERE codigo='DEMO-PORTA-ABERTURA'),5);
