# SQL do Falhas GPT — escolha uma rota

Estes arquivos configuram a aplicação em um projeto Supabase. Não criam a sua conta Supabase nem substituem os serviços Auth/Storage. São a estrutura e as regras; não contêm seus procedimentos, usuários reais ou PDFs.

| Situação | Execute no SQL Editor, nesta ordem |
| --- | --- |
| Projeto Supabase novo, ainda sem schema `falhas_gpt` | `instalacao/00_DIAGNOSTICO.sql`, `instalacao/01_INSTALAR_COMPLETO_V5.sql`, `instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql` |
| V4 instalada | `v5/04_ATUALIZAR_V4_PARA_V5.sql`, `instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql` |
| V5 instalada com a correção de 08/10 | Somente `instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql`; não há nova migração para hospedar em Pages |
| SQL 04 anterior falhou no SET pg_trgm | Execute o `v5/04_ATUALIZAR_V4_PARA_V5.sql` deste pacote inteiro e depois a validação completa |
| Schema antigo sem V4, ou diagnóstico diferente | Não rode o instalador novo por cima. Os arquivos de histórico estão presentes para manutenção, mas a compatibilidade deve ser verificada antes |

No instalador **novo**, substitua apenas `COLE_UUID_ADMIN_AQUI` pelo UUID da conta criada em **Authentication > Users** no projeto novo. O UUID antigo não se transfere automaticamente para outro Supabase. O instalador bloqueia execução sobre um schema existente e não apaga dados.

Execute cada arquivo completo, sem selecionar fragmentos. Se surgir erro, pare e guarde a mensagem. Se a sessão ficar com transação abortada, execute `ROLLBACK;` antes de tentar novamente. A instalação e a atualização usam transação.

Não execute todos os SQLs da pasta em sequência. Os arquivos V3/V4 e fragmentos `migration.sql` / `admin_re_migration.sql` estão incluídos como fontes históricas e para os testes; não são passos adicionais após a V5. Nunca rode `02_exemplos_para_validar.sql` no acervo real: contém apenas exemplos fictícios.

Em `docs/01_SUPABASE.md` estão os passos de Auth, administrador, RE, Storage, chave pública e URLs de retorno. Isso precisa ser configurado no painel além do SQL. Nenhuma Edge Function, cron ou chave de OpenAI é necessária para esta versão.

Para regenerar os SQLs a partir das fontes (manutenção do código, opcional):

```powershell
python scripts/package-v4.py
python scripts/package-v5.py
python scripts/package-install.py
```

Esse comando sobrescreve o instalador gerado e restaura o marcador de UUID; não o rode depois de preencher o arquivo para aplicação sem revisar novamente.
