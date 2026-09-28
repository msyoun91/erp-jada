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
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="t-h1">Dashboard</h1>
        {widgets.length > 0 && <ConfigurarWidgets widgets={widgets} prefs={prefs} />}
      </div>

      {visibles.length === 0 ? (
        <div className="empty-state">Sin widgets visibles. Activalos en Configurar.</div>
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
    </div>
  );
}
