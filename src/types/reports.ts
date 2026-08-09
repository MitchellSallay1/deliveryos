export type ReportPeriod = 'day' | 'week' | 'month'

export type ReportSummary = {
  period: string
  from: string
  to: string
  total: number
  completed: number
  failed: number
  cancelled: number
  in_progress: number
  cod_collected_lrd_cents: number
  delivery_fees_lrd_cents: number
  avg_delivery_minutes: number | null
}

export type TopRiderReport = {
  rider_code: string
  full_name: string
  completed_deliveries: number
  rating: number
  period_completed: number
}

export type WorkspaceReport = {
  summary: ReportSummary
  top_riders: TopRiderReport[]
}
