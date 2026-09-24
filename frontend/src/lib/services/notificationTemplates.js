function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

export const TEMPLATES = {
  // 1. Session Revisions Due
  revision_due: (data) => {
    const pool = [
      {
        title: '⏳ Session Review Due!',
        body: `Your log from ${data.date} is waiting for Revision P${data.rev}. Keep that memory curve steep!`
      },
      {
        title: '🧠 Don\'t Let It Fade!',
        body: `${data.date} is scheduled for Revision P${data.rev} today. A quick glance locks it in.`
      },
      {
        title: '🔄 Retention Check Time',
        body: `Day ${data.date} needs review today (P${data.rev}). Secure your immersion multiplier!`
      },
      {
        title: '📖 Time for a Quick Walkback',
        body: `Check off the P${data.rev} revision for ${data.date} and keep your review backlog clean.`
      }
    ];
    return pickRandom(pool);
  },

  // 2. SRS Flashcards Due
  srs_due: (data) => {
    const pool = [
      {
        title: `🎯 ${data.totalDue} Flashcards Calling!`,
        body: `${data.audioDue} audio & ${data.visualDue} visual cards due in Quiz Arena. Knock them out!`
      },
      {
        title: '⚡ Fresh SRS Reviews Ready',
        body: `You have ${data.totalDue} cards due for ${data.lang}. 3 minutes to clear the queue!`
      },
      {
        title: '🔥 Quiz Arena Awaits',
        body: `${data.totalDue} cards need attention today. Protect your recall retention!`
      },
      {
        title: '🎧 Active Recall Time',
        body: `${data.totalDue} items due for review. Keep your vocabulary recognition instant.`
      }
    ];
    return pickRandom(pool);
  },

  // 3. Mid-Day / Evening Nudge (Partial Progress)
  partial_goal_nudge: (data) => {
    const pool = [
      {
        title: '⚡ Almost to the Finish Line!',
        body: `You've logged ${data.loggedWords}/${data.goalWords} words and ${data.loggedListen}/${data.goalListen}m audio. Close the gap!`
      },
      {
        title: '🔥 Keep the Momentum Alive',
        body: `Just ${data.wordsLeft} more words and ${data.listenLeft}m of listening to turn today\'s rings green.`
      },
      {
        title: '🎯 One Last Push Today',
        body: `You\'re ${data.pct}% of the way through today\'s targets. Wrap it up before bed!`
      },
      {
        title: '💪 Finish Today Strong',
        body: `Only ${data.wordsLeft} words & ${data.listenLeft}m immersion left. Your future self thanks you.`
      }
    ];
    return pickRandom(pool);
  },

  // 4. Inactive Streak Protector (0 progress logged by evening)
  streak_warning: (data) => {
    const pool = [
      {
        title: '🚨 Protect Your Streak!',
        body: `No progress logged yet today for ${data.lang}. Log just 1 word or audio clip to keep it alive!`
      },
      {
        title: `🔥 Don't Break the Chain!`,
        body: `Your ${data.currentStreak}-day streak is on the line. Jump in for a quick 5-minute session!`
      },
      {
        title: '⏳ Day is Wrapping Up',
        body: `A single activity saves your ${data.currentStreak}d streak. Log a quick review before midnight!`
      }
    ];
    return pickRandom(pool);
  },

  // 5. Daily Victory Lap (All Goals Cleared)
  all_goals_cleared: (data) => {
    const pool = [
      {
        title: '🏆 Daily Targets Crushed!',
        body: `All goals complete for ${data.lang}! Streak extended to ${data.streak} days. Incredible consistency.`
      },
      {
        title: '✨ Mission Complete Today',
        body: `Every single ring closed: words, listening, and speaking. Take a bow and rest up!`
      },
      {
        title: '🌟 Gold Standard Day',
        body: `100% daily targets achieved. You\'re making massive strides in ${data.lang}.`
      }
    ];
    return pickRandom(pool);
  },

  // 6. Cumulative Milestone Unlocked
  milestone_unlocked: (data) => {
    const pool = [
      {
        title: '🎉 Cumulative Milestone Unlocked!',
        body: `You just surpassed ${data.count} ${data.unit} in ${data.lang}! True compounding at work.`
      },
      {
        title: '🚀 Level Up!',
        body: `${data.count} ${data.unit} officially logged. Every single session builds the foundation.`
      }
    ];
    return pickRandom(pool);
  }
};