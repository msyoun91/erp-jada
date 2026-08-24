export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      submodulos: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          id: string
          modulo: string
          nombre: string
          orden: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at: string
          vista_id: string | null
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          id?: string
          modulo: string
          nombre: string
          orden?: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          id?: string
          modulo?: string
          nombre?: string
          orden?: number
          tipo?: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey"
            columns: ["vista_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          descripcion: string | null
          estado: Database["public"]["Enums"]["estado_tarea"]
          fecha_vencimiento: string | null
          hilo_id: string | null
          id: string
          modo_completado: Database["public"]["Enums"]["modo_completado"]
          nota_anterior: string | null
          nota_siguiente: string | null
          origen_app: string | null
          origen_punto: string | null
          paso_anterior_id: string | null
          posponer_desde: string | null
          posponer_hasta: string | null
          proyecto_id: string | null
          recurrencia_cantidad: number | null
          recurrencia_unidad:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id: string
          temperatura: number
          titulo: string
          updated_at: string
          visibilidad: Database["public"]["Enums"]["visibilidad"]
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          fecha_vencimiento?: string | null
          hilo_id?: string | null
          id?: string
          modo_completado?: Database["public"]["Enums"]["modo_completado"]
          nota_anterior?: string | null
          nota_siguiente?: string | null
          origen_app?: string | null
          origen_punto?: string | null
          paso_anterior_id?: string | null
          posponer_desde?: string | null
          posponer_hasta?: string | null
          proyecto_id?: string | null
          recurrencia_cantidad?: number | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id: string
          temperatura?: number
          titulo: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          fecha_vencimiento?: string | null
          hilo_id?: string | null
          id?: string
          modo_completado?: Database["public"]["Enums"]["modo_completado"]
          nota_anterior?: string | null
          nota_siguiente?: string | null
          origen_app?: string | null
          origen_punto?: string | null
          paso_anterior_id?: string | null
          posponer_desde?: string | null
          posponer_hasta?: string | null
          proyecto_id?: string | null
          recurrencia_cantidad?: number | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id?: string
          temperatura?: number
          titulo?: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Relationships: [
          {
            foreignKeyName: "tareas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_paso_anterior_id_fkey"
            columns: ["paso_anterior_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_proyecto_id_fkey"
            columns: ["proyecto_id"]
            isOneToOne: false
            referencedRelation: "tareas_proyectos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_asignados: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          tarea_id: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          tarea_id: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          tarea_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_asignados_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_asignados_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_eventos: {
        Row: {
          created_at: string
          estado_anterior: Database["public"]["Enums"]["estado_tarea"] | null
          estado_nuevo: Database["public"]["Enums"]["estado_tarea"]
          id: string
          tarea_id: string
          usuario_id: string | null
        }
        Insert: {
          created_at?: string
          estado_anterior?: Database["public"]["Enums"]["estado_tarea"] | null
          estado_nuevo: Database["public"]["Enums"]["estado_tarea"]
          id?: string
          tarea_id: string
          usuario_id?: string | null
        }
        Update: {
          created_at?: string
          estado_anterior?: Database["public"]["Enums"]["estado_tarea"] | null
          estado_nuevo?: Database["public"]["Enums"]["estado_tarea"]
          id?: string
          tarea_id?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_eventos_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_eventos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_hilos: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          descripcion: string | null
          estado: Database["public"]["Enums"]["estado_hilo"]
          id: string
          posponer_desde: string | null
          posponer_hasta: string | null
          proyecto_id: string | null
          responsable_id: string
          titulo: string
          updated_at: string
          visibilidad: Database["public"]["Enums"]["visibilidad"]
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          posponer_desde?: string | null
          posponer_hasta?: string | null
          proyecto_id?: string | null
          responsable_id: string
          titulo: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          posponer_desde?: string | null
          posponer_hasta?: string | null
          proyecto_id?: string | null
          responsable_id?: string
          titulo?: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_proyecto_id_fkey"
            columns: ["proyecto_id"]
            isOneToOne: false
            referencedRelation: "tareas_proyectos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_hilos_notas: {
        Row: {
          activo: boolean
          created_at: string
          hilo_id: string
          id: string
          nota: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          hilo_id: string
          id?: string
          nota: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          hilo_id?: string
          id?: string
          nota?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_notas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_notas_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_notas: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nota: string
          tarea_id: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nota: string
          tarea_id: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nota?: string
          tarea_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_notas_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_plantillas: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          descripcion: string | null
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          descripcion?: string | null
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          descripcion?: string | null
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_plantillas_items: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          orden: number
          plantilla_id: string
          titulo: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          orden?: number
          plantilla_id: string
          titulo: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          orden?: number
          plantilla_id?: string
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_items_plantilla_id_fkey"
            columns: ["plantilla_id"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_proyectos: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          descripcion: string | null
          id: string
          nombre: string
          updated_at: string
          visibilidad: Database["public"]["Enums"]["visibilidad"]
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          descripcion?: string | null
          id?: string
          nombre: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          descripcion?: string | null
          id?: string
          nombre?: string
          updated_at?: string
          visibilidad?: Database["public"]["Enums"]["visibilidad"]
        }
        Relationships: [
          {
            foreignKeyName: "tareas_proyectos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_proyectos_miembros: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          proyecto_id: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          proyecto_id: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          proyecto_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_proyectos_miembros_proyecto_id_fkey"
            columns: ["proyecto_id"]
            isOneToOne: false
            referencedRelation: "tareas_proyectos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_proyectos_miembros_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_submodulos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          submodulo_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          submodulo_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          submodulo_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_widgets: {
        Row: {
          created_at: string
          id: string
          updated_at: string
          usuario_id: string
          visible: boolean
          widget_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id: string
          visible?: boolean
          widget_id: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id?: string
          visible?: boolean
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          activo: boolean
          created_at: string
          email: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          email: string
          id: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          email?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      es_asignado_tarea: { Args: { p_tarea_id: string }; Returns: boolean }
      es_creador_proyecto: { Args: { p_proyecto_id: string }; Returns: boolean }
      es_miembro_proyecto: {
        Args: { p_proyecto_id: string; p_usuario_id: string }
        Returns: boolean
      }
      es_miembro_proyecto_de_tarea: {
        Args: { p_tarea_id: string; p_usuario_id: string }
        Returns: boolean
      }
      es_responsable_o_creador_tarea: {
        Args: { p_tarea_id: string }
        Returns: boolean
      }
      puede_ver_hilo: { Args: { p_hilo_id: string }; Returns: boolean }
      reactivar_posponer_vencidos: { Args: never; Returns: undefined }
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean }
    }
    Enums: {
      estado_hilo: "abierto" | "cerrado"
      estado_tarea: "pendiente" | "en_progreso" | "completada" | "cancelada"
      modo_completado: "manual" | "automatico" | "hibrido"
      recurrencia_unidad: "dia" | "mes"
      tipo_submodulo: "vista" | "funcion"
      visibilidad: "publico" | "privado"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      estado_hilo: ["abierto", "cerrado"],
      estado_tarea: ["pendiente", "en_progreso", "completada", "cancelada"],
      modo_completado: ["manual", "automatico", "hibrido"],
      recurrencia_unidad: ["dia", "mes"],
      tipo_submodulo: ["vista", "funcion"],
      visibilidad: ["publico", "privado"],
    },
  },
} as const
