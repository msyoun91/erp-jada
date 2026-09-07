import type {
  EstadoObra,
  MotivoPerdida,
  Obra,
  OrigenObra,
  Provincia,
  TipoObra,
  Usuario,
} from "../types";

function Dato({ etiqueta, valor }: { etiqueta: string; valor: string | null }) {
  if (valor === null || valor === "") return null;
  return (
    <div>
      <dt className="t-caption">{etiqueta}</dt>
      <dd className="t-body-m">{valor}</dd>
    </div>
  );
}

export function DatosGenerales({
  obra,
  responsable,
  labels,
}: {
  obra: Obra;
  responsable: Usuario | null;
  labels: {
    estado: Record<EstadoObra, string>;
    tipo: Record<TipoObra, string>;
    origen: Record<OrigenObra, string>;
    provincia: Record<Provincia, string>;
    motivo: Record<MotivoPerdida, string>;
  };
}) {
  return (
    <section className="card p-4">
      <dl className="grid grid-cols-2 gap-4 md:grid-cols-3">
        <Dato etiqueta="Estado" valor={labels.estado[obra.estado]} />
        <Dato etiqueta="Tipo" valor={labels.tipo[obra.tipo]} />
        <Dato etiqueta="Responsable" valor={responsable?.nombre ?? null} />
        <Dato etiqueta="Dirección" valor={obra.direccion} />
        <Dato etiqueta="Localidad" valor={obra.localidad} />
        <Dato
          etiqueta="Provincia"
          valor={obra.provincia ? labels.provincia[obra.provincia] : null}
        />
        <Dato etiqueta="Origen" valor={obra.origen ? labels.origen[obra.origen] : null} />
      </dl>

      {obra.observaciones && (
        <p className="t-body-m mt-4 whitespace-pre-wrap">{obra.observaciones}</p>
      )}

      {/* El motivo se conserva aunque la obra salga de "perdida": es histórico. */}
      {obra.motivo_perdida && (
        <div className="mt-4 rounded-md border border-border bg-bg-subtle p-3">
          <p className="t-caption">
            Motivo de pérdida{obra.estado !== "perdida" && " (histórico)"}
          </p>
          <p className="t-body-m font-semibold">{labels.motivo[obra.motivo_perdida]}</p>
          {obra.detalle_perdida && (
            <p className="t-body-m mt-1 whitespace-pre-wrap">{obra.detalle_perdida}</p>
          )}
        </div>
      )}
    </section>
  );
}
