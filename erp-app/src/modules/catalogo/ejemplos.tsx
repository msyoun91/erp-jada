// Lo que muestra el "?" de cada campo difícil del catálogo. Todos usan la misma ventana corrediza, con los
// números de `decisiones/catalogo/`: si una regla cambia allá, el ejemplo se corrige acá.
// En una fórmula los números van sin punto de miles (`2000`), así que en `<code>` nunca llevan punto.

export const EJEMPLO = {
  // ---------- Editor: variables ----------
  variableNombre: (
    <>
      <p>
        <strong>Ancho de hoja 1</strong>: el vendedor lee este nombre, y en una fórmula se escribe{" "}
        <code>[Ancho de hoja 1]</code>.
      </p>
      <p>
        Con espacios va entre corchetes; un nombre de una palabra, como <code>ancho</code>, no los necesita.
      </p>
    </>
  ),
  lista: (
    <>
      <p>
        <strong>Mano</strong> de una puerta: valores Izquierda y Derecha, uno por renglón. Con predeterminado Izquierda,
        el vendedor solo la cambia si es Derecha; vacío, la tiene que elegir.
      </p>
      <p>No entra en ninguna cuenta: le llega a Producción con el despiece.</p>
    </>
  ),
  formula: (
    <>
      <p>
        <strong>Ancho de hoja</strong>: <code>(ancho + 50) / 2</code>. Con ancho 1.500 da 775: dos hojas que se solapan
        50 mm.
      </p>
      <p>
        Por escalones: <code>si alto &gt; 2100 entonces 4 si no 3</code>. El &quot;si no&quot; es obligatorio.
      </p>
    </>
  ),
  predeterminado: (
    <>
      <p>
        <strong>Ancho de hoja 1</strong> con predeterminado <code>(ancho + 50) / 2</code>: con ancho 2.000, al vendedor
        le aparece 1.025. Si no lo toca, las hojas salen iguales; si escribe otro número, queda el suyo.
      </p>
      <p>
        Vacío, el vendedor lo tiene que cargar, como <code>ancho</code> y <code>alto</code>.
      </p>
    </>
  ),
  queEs: (
    <>
      <p>
        <strong>ancho</strong> es una medida: el vendedor lee &quot;ancho (mm)&quot;.
      </p>
      <p>
        <strong>Cantidad de travesaños</strong>, de 0 a 3, es una cantidad: lee &quot;(u)&quot;. Las fórmulas usan el
        número igual en los dos casos.
      </p>
    </>
  ),
  rango: (
    <>
      <p>
        <strong>ancho</strong> de 300 a 3000: si el vendedor carga 150, el paquete se bloquea con &quot;Ancho va de 300
        a 3.000 mm&quot;.
      </p>
      <p>
        Un tope que depende de otra variable va en una condición: <code>alto &gt; ancho × 2</code>.
      </p>
    </>
  ),
  secundaria: (
    <p>
      <strong>Mano</strong>, con Izquierda de predeterminado, va plegada en &quot;Más opciones&quot;: el vendedor la
      abre solo para cambiarla. <code>ancho</code> y <code>alto</code> no tienen predeterminado, así que siempre están a
      la vista.
    </p>
  ),

  // ---------- Editor: piezas ----------
  piezaCantidad: (
    <>
      <p>
        <strong>Hoja × 2</strong>: armás una sola hoja (Perfil hoja 775 mm × 2) y el despiece la multiplica: 775 mm × 4.
      </p>
      <p>
        Con fórmula: la pieza Travesaño con cantidad <code>[Cantidad de travesaños]</code>; con 0 no lleva.
      </p>
    </>
  ),
  opcional: (
    <>
      <p>
        <strong>Mosquitero</strong>: opcional, sin incluir. El vendedor lo suma si el cliente lo pide.
      </p>
      <p>
        <strong>Burlete</strong>: opcional y &quot;viene incluida&quot;. El vendedor lo saca si no va.
      </p>
    </>
  ),
  requiere: (
    <p>
      <strong>Cortina</strong> requiere <strong>Cajón</strong>: al elegir la Cortina se marca también el Cajón, y si el
      Cajón no se ofrece en ese color, la Cortina tampoco.
    </p>
  ),
  calculaEspesor: (
    <>
      <p>
        <strong>Hoja</strong> con su Vidrio Float 4mm marcado &quot;cuenta para el espesor&quot;: la hoja da 4 mm.
      </p>
      <p>
        En una fórmula: <code>[espesor Hoja]</code>, como en la condición <code>[espesor Hoja] &gt; 24</code>. El peso
        se usa igual: <code>[peso Hoja]</code>.
      </p>
    </>
  ),

  // ---------- Editor: materiales ----------
  tipoMaterial: (
    <>
      <p>
        <strong>Único</strong>: Perfil marco 20x40, siempre el mismo.
      </p>
      <p>
        <strong>Lo elige el vendedor</strong>: Vidrio, con las opciones Float 4mm y Laminado 3+3.
      </p>
      <p>
        <strong>Lo define el sistema</strong>: Rueda 40kg o Rueda 80kg, según el peso de la hoja.
      </p>
      <p>
        <strong>Sigue a otro</strong>: Contravidrio, que toma la pareja del vidrio elegido.
      </p>
    </>
  ),
  regla: (
    <>
      <p>
        <code>si [peso Hoja] &gt; 40 entonces [Rueda 80kg] si no [Rueda 40kg]</code>: una hoja de 16 kg lleva la de 40
        kg.
      </p>
      <p>
        Cada rama termina en una opción, con el nombre de su insumo, o en <code>ninguno</code>. El &quot;si no&quot; es
        obligatorio.
      </p>
    </>
  ),
  medida: (
    <>
      <p>
        <strong>Perfil marco</strong>: medida <code>ancho - 2</code> y cantidad 2. Con ancho 1.500, dos cortes de 1.498
        mm.
      </p>
      <p>
        En un insumo en u la medida es opcional y solo le dice a Producción cómo cortar: una varilla roscada{" "}
        <code>300</code> × 2 se cobra como 2 u.
      </p>
    </>
  ),
  anchoAlto: (
    <p>
      <strong>Vidrio</strong> de la hoja: ancho <code>[Ancho de hoja] - 48</code> y alto <code>alto - 48</code>. Con
      hoja de 775 y alto 1.100 da 727 × 1.052 mm, y el sistema lo pasa a m2: 0,76 m2.
    </p>
  ),
  area: (
    <>
      <p>
        Solo para lo que no es un rectángulo. Vidrio de un arco rebajado, con las variables <code>radio</code> y{" "}
        <code>flecha</code>:
      </p>
      <p>
        <code>radio × radio × arcoseno(ancho / (2 × radio)) − ancho / 2 × (radio − flecha)</code>
      </p>
      <p>Con ancho 1.200 y flecha 200 da 163.501 mm²: 0,16 m2, y no los 0,24 del rectángulo de 1.200 × 200.</p>
    </>
  ),
  cantidad: (
    <>
      <p>
        <strong>Ruedas</strong>: <code>4</code>, sin medida.
      </p>
      <p>
        <strong>Bisagras</strong>, una cada 700 mm: <code>redondear_arriba(alto / 700)</code>. Con alto 2.000 da 3.
      </p>
      <p>
        Decimales con coma: <code>0,5</code>.
      </p>
    </>
  ),
  sinEleccion: (
    <p>
      <strong>Manija</strong> con &quot;sin elección&quot;: el vendedor puede dejar la ventana sin manija. Como puede
      faltar, ninguna fórmula usa ese material.
    </p>
  ),
  cuentaEspesor: (
    <p>
      En la Hoja, el <strong>Vidrio</strong> cuenta para el espesor (4 mm) y el Perfil hoja no. La Rueda que se elige
      por <code>[peso Hoja]</code> no cuenta para el peso: sería circular.
    </p>
  ),
  parejas: (
    <>
      <p>
        <strong>Contravidrio</strong> que sigue al Vidrio: Float 4mm → Contravidrio 4mm, Laminado 3+3 → Contravidrio
        6mm, DVH → &quot;Ninguna: no lleva&quot;.
      </p>
      <p>
        &quot;Mismas opciones&quot; es para el sincronizado: el Vidrio de la Hoja 2 queda con el mismo vidrio que el de
        la Hoja 1.
      </p>
    </>
  ),
  opcionMedida: (
    <>
      <p>Vacío, cada dato se hereda del material por separado; la medida, solo si la opción tiene la misma unidad.</p>
      <p>
        <strong>Mosquitero</strong>: la Tela (m2) hereda el ancho y el alto del material, y el Enrollable (u) no hereda
        la medida.
      </p>
    </>
  ),
  opcionCantidad: (
    <p>
      <strong>Rueda</strong> con cantidad 4: la Rueda simple la deja vacía y hereda 4; la Rueda tándem trae{" "}
      <code>2</code>.
    </p>
  ),

  // ---------- Editor: condiciones y colores ----------
  condiciones: (
    <>
      <p>
        <code>alto &gt; ancho × 2</code> → alerta: &quot;Muy alta para su ancho: revisá las medidas&quot;.
      </p>
      <p>
        <code>ancho &gt; 2000 y alto &gt; 2400</code> → bloquea: &quot;Pasa el máximo del vidrio&quot;.
      </p>
      <p>
        Para mezclar <code>y</code> con <code>o</code> van paréntesis:{" "}
        <code>(ancho &gt; 2000 o alto &gt; 2400) y [Vidrio] &gt; 3500000</code>. Los números, sin punto de miles.
      </p>
    </>
  ),
  coloresVersion: (
    <p>
      <strong>Blanco</strong> (base) y <strong>Negro</strong>: el vendedor ve la ventana en blanco y la puede cambiar.
      Si el Mosquitero solo existe en blanco, en negro se ofrece la ventana sin Mosquitero.
    </p>
  ),

  // ---------- Insumos y servicios fijos ----------
  unidad: (
    <>
      <p>
        <strong>mm</strong>: perfiles. El costo y el peso van por metro.
      </p>
      <p>
        <strong>m2</strong>: vidrios y telas. El material lleva ancho y alto.
      </p>
      <p>
        <strong>u</strong>: ruedas, manijas, tornillos. Se cobra la cantidad.
      </p>
    </>
  ),
  pesoEspesor: (
    <>
      <p>
        <strong>Peso</strong>: Perfil hoja (mm) 0,65 kg/m · Float 4mm (m2) 10 kg/m2 · Rueda (u) 0,1 kg/u.
      </p>
      <p>
        <strong>Espesor</strong>: Float 4mm, 4 · DVH 4+12+4, 20. Si no lo sabés, dejalo vacío.
      </p>
    </>
  ),
  coloresInsumo: (
    <p>
      <strong>Perfil hoja</strong>: Blanco y Negro, cada uno con su costo. Un tornillo que va en cualquier ventana no
      lleva ninguno: es de color indistinto.
    </p>
  ),
  unidadFijo: (
    <p>
      <strong>Soldado</strong> en u: $1.800 por soldadura, y el material dice cuántas. <strong>Instalación</strong> en
      u: un monto por ventana. Un servicio en m2 se cobra por el área.
    </p>
  ),
  cambiarTodos: (
    <p>
      <code>8</code>: un costo de $1.000 pasa a $1.080. <code>-5</code>: pasa a $950. Cada fila queda en su moneda, las
      que no tienen costo no cambian, y nada se guarda hasta revisar.
    </p>
  ),

  // ---------- Servicios en % ----------
  paso: (
    <>
      <p>Con un despiece de $200.000, del que $60.000 son Vidrios:</p>
      <p>
        <strong>Paso 1</strong>: Garantía de vidrio 5 % sobre Vidrios → $3.000. Comercialización 10 % sin categorías,
        sobre todo el despiece → $20.000. Subtotal: $223.000.
      </p>
      <p>
        <strong>Paso 2</strong>: Transición 4 % del subtotal → $8.920. Quedan $231.920.
      </p>
      <p>
        <strong>Paso 3</strong>: IIBB 3 %, despejado: 231.920 / 0,97 = $239.093, y el IIBB es el 3 % exacto de ese
        precio.
      </p>
    </>
  ),
  minimo: (
    <>
      <p>
        <strong>Por paquete</strong>: Comercialización 10 %, mínimo $15.000. Un despiece de $100.000 paga $15.000, no
        $10.000.
      </p>
      <p>
        <strong>Por presupuesto</strong>: Garantía de vidrio 5 %, mínimo $10.000. Si todo el presupuesto junta $9.000,
        los $1.000 que faltan van en un renglón aparte.
      </p>
    </>
  ),
};
