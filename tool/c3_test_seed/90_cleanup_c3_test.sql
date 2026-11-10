-- TEMPLATE cleanup — TEST only. Deletes ONLY c3_test tagged rows / @fleaber.test.
-- Review joins before run. Never point at PROD.
--
-- delete from messages where metadata->>'c3_test' = '1';
-- delete from orders where metadata->>'c3_test' = '1';
-- delete from products where metadata->>'c3_test' = '1';
-- delete from profiles where email like '%@fleaber.test';
SELECT 'C3_TEST_CLEANUP_TEMPLATE_NOT_APPLIED' AS status;
