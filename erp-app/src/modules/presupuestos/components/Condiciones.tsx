// Las particulares de la versión y los términos generales: lo mismo en el editor y en el impreso.
export function Condiciones({ particulares, generales }: { particulares?: string | null; generales?: string | null }) {
  return (
    <>
      {particulares && <Bloque titulo="Condiciones particulares" texto={particulares} />}
      {generales && <Bloque titulo="Términos y condiciones" texto={generales} />}
    </>
  );
}

function Bloque({ titulo, texto }: { titulo: string; texto: string }) {
  return (
    <div className="print:break-inside-avoid">
      <p className="t-label mb-1">{titulo}</p>
      <p className="t-body-m whitespace-pre-line">{texto}</p>
    </div>
  );
}
