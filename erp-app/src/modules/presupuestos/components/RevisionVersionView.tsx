import Link from "next/link";
import { TriangleAlert } from "lucide-react";
import type { RevisionVersion } from "../queries";
import { ResolverTecnica } from "./ResolverTecnica";

type Renglon = RevisionVersion["renglones"][number];

// Una versión para Técnica: lo que espera arriba y el resto en su orden, sin precios ni obra (decisiones/presupuestos.md →
// *Pantallas*). `autoriza`: tiene la función, que la base vuelve a verificar. `despiece`: ve los paquetes en Catálogo.
export function RevisionVersionView({
  datos,
  autoriza,
  despiece,
}: {
  datos: RevisionVersion;
  autoriza: boolean;
  despiece: boolean;
}) {
  const esperan = datos.renglones.filter((r) => r.pedido_estado === "pendiente");
  const resto = datos.renglones.filter((r) => r.pedido_estado !== "pendiente");

  return (
    <div className="flex flex-col gap-4">
      <div className="card">
        <h2 className="t-h2">
          {datos.codigo} · v{datos.version}
        </h2>
        {esperan.length === 0 && <p className="t-caption mt-1">Nada espera tu revisión en esta versión.</p>}
      </div>

      {esperan.length > 0 && (
        <section className="card" aria-label="Esperan tu revisión">
          <h3 className="t-h3 mb-2">Esperan tu revisión</h3>
          <ul className="flex flex-col">
            {esperan.map((r) => (
              <Ventana key={r.renglon_id} r={r} despiece={despiece}>
                {autoriza && r.pedido_id && <ResolverTecnica pedidoId={r.pedido_id} etiqueta={etiqueta(r)} />}
              </Ventana>
            ))}
          </ul>
        </section>
      )}

      {resto.length > 0 && (
        <section className="card" aria-label={esperan.length > 0 ? "El resto de la versión" : "La versión"}>
          <h3 className="t-h3 mb-2">
            {esperan.length > 0 ? `El resto de la versión (${resto.length})` : "La versión"}
          </h3>
          <ul className="flex flex-col">
            {resto.map((r) => (
              <Ventana key={r.renglon_id} r={r} despiece={despiece} />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function etiqueta(r: Renglon) {
  return [r.designacion, r.ubicacion].filter(Boolean).join(" · ") || r.paquete || r.descripcion || "—";
}

// Lo que se pidió, si hay pedido; si no, las alertas de cuando se calculó.
function Ventana({ r, despiece, children }: { r: Renglon; despiece: boolean; children?: React.ReactNode }) {
  const mano = r.tipo === "mano";
  const titulo = [
    r.designacion,
    r.ubicacion,
    mano ? r.descripcion : r.paquete && `${r.paquete} (v${r.catalogo_version})`,
  ]
    .filter(Boolean)
    .join(" · ");
  const alertas = r.motivos.length > 0 ? r.motivos.map((mensaje) => ({ mensaje, bloquea: false })) : r.mensajes;
  const estado =
    r.pedido_estado === "pendiente"
      ? null
      : r.cubierta
        ? { label: "Autorizada", badge: "badge-success" }
        : r.pedido_estado === "devuelta"
          ? { label: "Devuelta", badge: "badge-warning" }
          : null;

  return (
    <li className="row flex flex-col gap-1 border-b border-border last:border-b-0">
      <p className="t-body-m font-medium text-text-primary">
        {titulo || "—"}
        {r.cantidad !== 1 && <span className="t-caption ml-2">× {r.cantidad.toLocaleString("es-AR")}</span>}
        {mano && <span className="badge badge-neutral ml-2 align-middle">A mano</span>}
        {estado && <span className={`badge ${estado.badge} ml-2 align-middle`}>{estado.label}</span>}
      </p>
      {r.cargado && <p className="t-caption">{r.cargado}</p>}
      {alertas.map((m) => (
        <p
          key={m.mensaje}
          className={`t-caption flex items-start gap-1 ${m.bloquea ? "text-error-text" : "text-warning-text"}`}
        >
          <TriangleAlert size={12} className="mt-0.5 shrink-0" />
          {m.mensaje}
        </p>
      ))}
      {despiece && r.catalogo_version_id && r.entrada && (
        <Link
          href={`/catalogo/paquetes/versiones/${r.catalogo_version_id}?entrada=${encodeURIComponent(JSON.stringify(r.entrada))}`}
          className="t-caption self-start underline"
        >
          Ver despiece
        </Link>
      )}
      {children}
    </li>
  );
}
