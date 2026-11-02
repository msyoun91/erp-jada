-- Prototipo que sostiene decisiones/catalogo.md → *Las fórmulas se calculan sin SQL dinámico*: vive en
-- pg_temp y termina en RAISE, así que no deja nada en la base. Las funciones reales salen de acá.
create function pg_temp.tok(f text) returns text[] language plpgsql as $$
declare s text := replace(replace(f,'−','-'),'×','*'); t text[];
begin
  select coalesce(array_agg(x[1] order by i),'{}') into t
  from regexp_matches(s,'(\d+(?:,\d+)?|\[[^\]]+\]|[[:alpha:]_][[:alnum:]_]*|<=|>=|<>|[-+*/()<>=])','g') with ordinality m(x,i);
  if regexp_replace(array_to_string(t,''),'\s','','g') is distinct from regexp_replace(s,'\s','','g') then raise exception 'caracter no permitido'; end if;
  return t;
end $$;

create function pg_temp.p_factor(t text[], p int) returns jsonb language plpgsql as $$
declare tk text := t[p]; r jsonb;
begin
  if tk is null then raise exception 'falta un valor'; end if;
  if tk ~ '^\d' then return jsonb_build_object('n',jsonb_build_object('op','num','v',replace(tk,',','.')),'p',p+1); end if;
  if tk = '-' then r := pg_temp.p_factor(t,p+1); return jsonb_build_object('n',jsonb_build_object('op','neg','a',r->'n'),'p',r->'p'); end if;
  if tk = '(' then
    r := pg_temp.p_expr(t,p+1);
    if t[(r->>'p')::int] is distinct from ')' then raise exception 'falta )'; end if;
    return jsonb_build_object('n',r->'n','p',(r->>'p')::int+1);
  end if;
  if tk ~ '^\[' then return jsonb_build_object('n',jsonb_build_object('op','var','v',btrim(tk,'[]')),'p',p+1); end if;
  if tk ~ '^[[:alpha:]_]' then
    if lower(tk) in ('si','entonces','no') then raise exception 'palabra inesperada: %', tk; end if;
    if t[p+1] = '(' then
      if lower(tk) not in ('redondear_arriba','arcoseno') then raise exception 'funcion no permitida: %', tk; end if;
      r := pg_temp.p_expr(t,p+2);
      if t[(r->>'p')::int] is distinct from ')' then raise exception 'falta )'; end if;
      return jsonb_build_object('n',jsonb_build_object('op',lower(tk),'a',r->'n'),'p',(r->>'p')::int+1);
    end if;
    if lower(tk) = 'pi' then return jsonb_build_object('n',jsonb_build_object('op','pi'),'p',p+1); end if;
    return jsonb_build_object('n',jsonb_build_object('op','var','v',tk),'p',p+1);
  end if;
  raise exception 'valor inesperado: %', tk;
end $$;

create function pg_temp.p_term(t text[], p int) returns jsonb language plpgsql as $$
declare a jsonb; b jsonb; o text;
begin
  a := pg_temp.p_factor(t,p);
  loop
    o := t[(a->>'p')::int];
    exit when o is null or o not in ('*','/');
    b := pg_temp.p_factor(t,(a->>'p')::int+1);
    a := jsonb_build_object('n',jsonb_build_object('op',o,'a',a->'n','b',b->'n'),'p',b->'p');
  end loop;
  return a;
end $$;

create function pg_temp.p_arith(t text[], p int) returns jsonb language plpgsql as $$
declare a jsonb; b jsonb; o text;
begin
  a := pg_temp.p_term(t,p);
  loop
    o := t[(a->>'p')::int];
    exit when o is null or o not in ('+','-');
    b := pg_temp.p_term(t,(a->>'p')::int+1);
    a := jsonb_build_object('n',jsonb_build_object('op',o,'a',a->'n','b',b->'n'),'p',b->'p');
  end loop;
  return a;
end $$;

create function pg_temp.p_cond(t text[], p int) returns jsonb language plpgsql as $$
declare a jsonb; b jsonb; o text;
begin
  a := pg_temp.p_arith(t,p);
  o := t[(a->>'p')::int];
  if o is null or o not in ('>','<','>=','<=','=','<>') then raise exception 'falta comparador'; end if;
  b := pg_temp.p_arith(t,(a->>'p')::int+1);
  return jsonb_build_object('n',jsonb_build_object('op','cmp','o',o,'a',a->'n','b',b->'n'),'p',b->'p');
end $$;

create function pg_temp.p_expr(t text[], p int) returns jsonb language plpgsql as $$
declare c jsonb; a jsonb; b jsonb; q int;
begin
  if lower(t[p]) = 'si' then
    c := pg_temp.p_cond(t,p+1);
    q := (c->>'p')::int;
    if lower(t[q]) is distinct from 'entonces' then raise exception 'falta entonces'; end if;
    a := pg_temp.p_expr(t,q+1);
    q := (a->>'p')::int;
    if lower(t[q]) is distinct from 'si' or lower(t[q+1]) is distinct from 'no' then raise exception 'falta si no'; end if;
    b := pg_temp.p_expr(t,q+2);
    return jsonb_build_object('n',jsonb_build_object('op','si','c',c->'n','a',a->'n','b',b->'n'),'p',b->'p');
  end if;
  return pg_temp.p_arith(t,p);
end $$;

create function pg_temp.parse(f text) returns jsonb language plpgsql as $$
declare t text[]; r jsonb;
begin
  t := pg_temp.tok(f);
  r := pg_temp.p_expr(t,1);
  if (r->>'p')::int <= coalesce(array_length(t,1),0) then raise exception 'sobra: %', t[(r->>'p')::int]; end if;
  return r->'n';
end $$;

create function pg_temp.ev(n jsonb, v jsonb) returns numeric language plpgsql as $$
declare o text := n->>'op'; a numeric; b numeric; cumple boolean;
begin
  case o
    when 'num' then return (n->>'v')::numeric;
    when 'var' then
      if v->(n->>'v') is null then raise exception 'variable desconocida: %', n->>'v'; end if;
      return (v->>(n->>'v'))::numeric;
    when 'pi' then return pi()::numeric;
    when 'neg' then return -pg_temp.ev(n->'a',v);
    when 'si' then
      a := pg_temp.ev(n->'c'->'a',v);
      b := pg_temp.ev(n->'c'->'b',v);
      cumple := (case n->'c'->>'o' when '>' then a>b when '<' then a<b when '>=' then a>=b when '<=' then a<=b when '=' then a=b else a<>b end);
      if cumple then return pg_temp.ev(n->'a',v); else return pg_temp.ev(n->'b',v); end if;
    when 'redondear_arriba' then return ceil(pg_temp.ev(n->'a',v));
    when 'arcoseno' then return asin(pg_temp.ev(n->'a',v)::float8)::numeric;
    else
      a := pg_temp.ev(n->'a',v);
      b := pg_temp.ev(n->'b',v);
      case o when '+' then return a+b; when '-' then return a-b; when '*' then return a*b; when '/' then return a/b; end case;
  end case;
end $$;

create function pg_temp.calcular(defs jsonb, entrada jsonb) returns jsonb language plpgsql as $$
declare v jsonb := entrada; faltan jsonb := defs; k text; f text; ast jsonb; avance boolean;
begin
  while faltan <> '{}'::jsonb loop
    avance := false;
    for k, f in select key, value from jsonb_each_text(faltan) loop
      ast := pg_temp.parse(f);
      if not exists (select 1 from jsonb_array_elements_text(jsonb_path_query_array(ast,'$.** ? (@.op == "var").v')) d where v->d.value is null) then
        v := v || jsonb_build_object(k, pg_temp.ev(ast,v));
        faltan := faltan - k;
        avance := true;
      end if;
    end loop;
    if not avance then raise exception 'referencia circular o desconocida'; end if;
  end loop;
  return v;
end $$;

do $$
declare
  ok int := 0; tot int := 0; fallas text := ''; c record; r numeric; err text;
  t0 timestamptz; ast jsonb; ms_parse numeric; ms_eval numeric; i int; res jsonb;
  f_vidrio text := 'radio × radio × arcoseno(ancho / (2 × radio)) − ancho / 2 × (radio − flecha)';
begin
  for c in select * from (values
    ('marco','ancho - 2','{"ancho":1500}'::jsonb,1498::numeric,null::text),
    ('radio','flecha / 2 + ancho * ancho / (8 * flecha)','{"ancho":1200,"flecha":200}',1000,null),
    ('perfil curvo','2 * radio * arcoseno(ancho / (2 * radio))','{"ancho":1200,"radio":1000}',1287.002,null),
    ('vidrio arco',f_vidrio,'{"ancho":1200,"flecha":200,"radio":1000}',163501.109,null),
    ('medio punto','2 * radio * arcoseno(ancho / (2 * radio))','{"ancho":1200,"radio":600}',1884.956,null),
    ('pi','pi * radio','{"radio":600}',1884.956,null),
    ('bisagras 2000','si alto > 2100 entonces 4 si no 3','{"alto":2000}',3,null),
    ('bisagras 2200','si alto > 2100 entonces 4 si no 3','{"alto":2200}',4,null),
    ('redondear','redondear_arriba(alto / 700)','{"alto":2000}',3,null),
    ('redondear exacto','redondear_arriba(alto / 700)','{"alto":2100}',3,null),
    ('si encadenado','si peso > 80 entonces 3 si no si peso > 40 entonces 2 si no 1','{"peso":50}',2,null),
    ('decimal con coma','0,5 * 3','{}',1.5,null),
    ('nombre con espacio','[Perfil hoja] * 2','{"Perfil hoja":3950}',7900,null),
    ('prioridad','2 + 3 * 4','{}',14,null),
    ('parentesis','(2 + 3) * 4','{}',20,null),
    ('asociatividad','10 - 2 - 3','{}',5,null),
    ('negativo','-2 + 5','{}',3,null),
    ('division por cero','flecha / 2 + ancho * ancho / (8 * flecha)','{"ancho":1200,"flecha":0}',null,'22012'),
    ('arcoseno fuera de rango','arcoseno(2)','{}',null,'22003'),
    ('sin si no','si alto > 2100 entonces 4','{"alto":2000}',null,'falta si no'),
    ('variable desconocida','ancho - 2','{}',null,'variable desconocida'),
    ('punto de miles','1.500','{}',null,'caracter no permitido'),
    ('punto de miles en si','si ancho > 1.500 entonces 1 si no 0','{"ancho":2000}',null,'caracter no permitido'),
    ('inyeccion punto y coma','1; drop table usuarios','{}',null,'caracter no permitido'),
    ('inyeccion comilla','ancho'' or 1=1','{"ancho":1}',null,'caracter no permitido'),
    ('inyeccion select','select 1','{}',null,'sobra'),
    ('inyeccion subconsulta','(select 1)','{}',null,'falta )'),
    ('funcion ajena','pg_sleep(10)','{}',null,'funcion no permitida'),
    ('vacia','','{}',null,'falta un valor')
  ) as x(nombre,f,v,esp,error) loop
    tot := tot + 1;
    begin
      r := pg_temp.ev(pg_temp.parse(c.f), c.v); err := null;
    exception when others then r := null; err := sqlstate || ':' || sqlerrm;
    end;
    if c.error is null then
      if r is not null and abs(r - c.esp) < 0.01 then ok := ok + 1;
      else fallas := fallas || c.nombre || ' (dio ' || coalesce(r::text, err) || '); '; end if;
    else
      if err like '%' || c.error || '%' then ok := ok + 1;
      else fallas := fallas || c.nombre || ' (dio ' || coalesce(err, r::text) || '); '; end if;
    end if;
  end loop;

  tot := tot + 1;
  begin
    res := pg_temp.calcular(jsonb_build_object('vidrio',f_vidrio,'perfil','2 * radio * arcoseno(ancho / (2 * radio))','radio','flecha / 2 + ancho * ancho / (8 * flecha)'),'{"ancho":1200,"flecha":200}');
    if abs((res->>'perfil')::numeric - 1287.002) < 0.01 and abs((res->>'vidrio')::numeric - 163501.109) < 0.01 then ok := ok + 1;
    else fallas := fallas || 'orden libre (dio ' || res::text || '); '; end if;
  exception when others then fallas := fallas || 'orden libre (' || sqlerrm || '); ';
  end;

  tot := tot + 1;
  begin
    res := pg_temp.calcular('{"a":"b + 1","b":"a + 1"}','{}');
    fallas := fallas || 'circular no detectada; ';
  exception when others then
    if sqlerrm like '%circular%' then ok := ok + 1; else fallas := fallas || 'circular (' || sqlerrm || '); '; end if;
  end;

  t0 := clock_timestamp();
  for i in 1..200 loop ast := pg_temp.parse(f_vidrio); end loop;
  ms_parse := extract(epoch from clock_timestamp() - t0) * 1000 / 200;
  t0 := clock_timestamp();
  for i in 1..1000 loop r := pg_temp.ev(ast,'{"ancho":1200,"flecha":200,"radio":1000}'); end loop;
  ms_eval := extract(epoch from clock_timestamp() - t0) * 1000 / 1000;

  raise exception '% / % ok | parsear % ms | evaluar % ms | ast % bytes | fallan: %', ok, tot, round(ms_parse,3), round(ms_eval,4), length(ast::text), fallas;
end $$;
