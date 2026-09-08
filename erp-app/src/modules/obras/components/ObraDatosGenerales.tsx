import type {
  MotivoPerdida,
  Obra,
  OrigenObra,
  Provincia,
  TipoObra,
  Usuario,
} from "../types";
import { Dato, Observaciones } from "./Dato";

export function DatosGenerales({
  obra,
  responsable,
  labels,
}: {
  obra: Obra;
  responsable: Usuario | null;
  labels: {
    tipo: Record<TipoObra, string>;
    origen: Record<OrigenObra, string>;
    provincia: Record<Provincia, string>;
    motivo: Record<MotivoPerdida, string>;
  };
}) {
  return (
    <section className="card p-4">
      <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3">
        {/* El estado no está acá: es el badge del encabezado. */}
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

      <Observaciones texto={obra.observaciones} />

      {/* El motivo se conserva aunque la obra salga de "perdida": es histórico. */}
      {obra.motivo_perdida && (
        <div className="mt-4 rounded-md border border-border bg-bg-subtle p-3">
          <p className="t-caption">
            Motivo de pérdida{obra.estado !== "perdida" && " (histórico)"}
          </p>
          <p className="t-body-m font-semibold">{labels.motivo[obra.motivo_perdida]}</p>
          {obra.detalle_perdida && (
            <p className="t-body-m mt-1 whitespace-pre-wrap break-words">{obra.detalle_perdida}</p>
          )}
        </div>
      )}
    </section>
  );
}
