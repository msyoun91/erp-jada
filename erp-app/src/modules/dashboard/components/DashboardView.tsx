import { Modulo } from "@/components/layout/Modulo";
import { WidgetUsuarios } from "./WidgetUsuarios";
import { ConfigurarWidgets } from "./ConfigurarWidgets";
import type { DashboardData, WidgetDefinicion } from "../types";

type Props = {
  data: DashboardData;
  widgets: WidgetDefinicion[];
  prefs: Record<string, boolean>;
  // Widgets que dibuja su módulo, por id: `app/` los compone (GUIDE_ENTES §2.7).
  modulos: Partial<Record<string, React.ReactNode>>;
};

export function DashboardView({ data, widgets, prefs, modulos }: Props) {
  const visibles = widgets.filter((w) => prefs[w.id] ?? true);

  return (
    <Modulo modulo="dashboard" accion={widgets.length > 0 && <ConfigurarWidgets widgets={widgets} prefs={prefs} />}>
      {visibles.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin widgets a la vista</p>
          <p className="t-body-m mt-1">
            {widgets.length > 0 ? 'Elegí cuáles ver en "Configurar".' : "Todavía no tenés widgets habilitados."}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 [grid-auto-flow:dense]">
          {visibles.map((widget) => {
            if (widget.id === "usuarios") {
              return (
                <WidgetUsuarios
                  key={widget.id}
                  totalActivos={data.totalUsuariosActivos}
                  columnas={widget.columnas}
                />
              );
            }
            return <div key={widget.id} className={widget.columnas === 2 ? "sm:col-span-2" : ""}>{modulos[widget.id]}</div>;
          })}
        </div>
      )}
    </Modulo>
  );
}
