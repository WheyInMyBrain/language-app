<script>
  import TodayActionHub from '../components/TodayActionHub.svelte';
  import VocabSearchStream from '../components/VocabSearchStream.svelte';
  import DashboardMetrics from '../components/DashboardMetrics.svelte';

  let { onSelectDate } = $props();
</script>

<section class="w-full max-w-md lg:max-w-4xl xl:max-w-5xl mx-auto space-y-8 pt-2 pb-24 px-1 lg:px-4">
  <!-- 1. Priority Hub / Apple Activity Rings -->
  <TodayActionHub {onSelectDate} />

  <!-- 2. Virtualized Horizontal Vocab Search Track -->
  <VocabSearchStream {onSelectDate} />

  <!-- 3. Metrics, Milestones, Growth Chart & Heatmap -->
  <DashboardMetrics />
</section>