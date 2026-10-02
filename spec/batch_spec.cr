require "./spec_helper"

describe Flourite::BatchQueue do
  it "manages job queue correctly" do
    queue = Flourite::BatchQueue.new
    queue.add("a.mp4", "a_out.mp4") do
      video { codec(:h264) }
      audio { codec(:aac) }
    end

    queue.total_count.should eq(1)
    queue.completed_count.should eq(0)
    queue.failed_count.should eq(0)
    queue.jobs.first.status.should eq(Flourite::BatchJob::Status::Pending)
  end
end
