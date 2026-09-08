<script>
  import TodayActionHub from '../components/TodayActionHub.svelte';
  import VocabSearchStream from '../components/VocabSearchStream.svelte';
  import DashboardMetrics from '../components/DashboardMetrics.svelte';

  let { onSelectDate } = $props();
</script>

<section class="max-w-md mx-auto space-y-4 pt-2 pb-8 px-1">
  <!-- 1. Priority Hub / Apple Activity Rings -->
  <TodayActionHub {onSelectDate} />

  <!-- 2. Virtualized Horizontal Vocab Search Track -->
  <VocabSearchStream {onSelectDate} />

  <!-- 3. Metrics, Milestones, Growth Chart & Heatmap -->
  <DashboardMetrics />
</section>