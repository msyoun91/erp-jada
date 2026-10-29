-- get_advisors (0011 function_search_path_mutable) sobre las dos funciones puras de sql/156.
ALTER FUNCTION public.nivel_cambio(numeric, numeric) SET search_path = public;
ALTER FUNCTION public.monedas_formato(numeric) SET search_path = public;
