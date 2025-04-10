#!/bin/sh

# push to origin target_sync_branch
push_new_commits() {
    write_out -1 'Pushing synced data to target branch.'

    # TODO: figure out how this would work in local mode...
    # update remote url with token since it is not persisted during checkout step when syncing from a private repo
    if [ -n "${INPUT_TARGET_REPO_TOKEN}" ]; then
        git remote set-url origin "https://${GITHUB_ACTOR}:${INPUT_TARGET_REPO_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
    fi

    # Create a new branch for changes
    BEIJING_TIMESTAMP=$(TZ=Asia/Shanghai date +%Y%m%d%H%M%S)
    BRANCH_NAME="sync-update-${BEIJING_TIMESTAMP}"
    git checkout -b "${BRANCH_NAME}"
    
    # Push to the new branch instead of directly to target branch
    # shellcheck disable=SC2086
    git push origin "${BRANCH_NAME}"
    PUSH_STATUS=$?
    
    if [ "${PUSH_STATUS}" != 0 ]; then
        # exit on push to new branch fail
        write_out "${PUSH_STATUS}" "Could not push changes to new branch."
        return
    fi
    
    # Get last commit information for PR body
    LAST_COMMIT_HASH=$(git rev-parse HEAD)
    LAST_COMMIT_MSG=$(git log -1 --pretty=%B | sed 's/"/\\"/g' | tr '\n' ' ')
    LAST_COMMIT_AUTHOR=$(git log -1 --pretty=%an | sed 's/"/\\"/g')
    LAST_COMMIT_DATE=$(TZ=Asia/Shanghai git log -1 --pretty=%ad --date=format:'%Y-%m-%d %H:%M:%S')
    
    # Create PR if GitHub token is available
    if [ -n "${INPUT_TARGET_REPO_TOKEN}" ]; then
        PR_TITLE="Sync updates from source repository"
        
        # Create simplified PR body with proper JSON escaping
        PR_BODY="## Automated Sync Update\n\n### Changes included in this PR:\n- Latest commit: ${LAST_COMMIT_HASH}\n- Commit message: ${LAST_COMMIT_MSG}\n- Author: ${LAST_COMMIT_AUTHOR}\n- Date: ${BEIJING_TIMESTAMP}\n\nThis PR was automatically created by the sync workflow."
        
        # Create JSON payload for PR creation
        JSON_PAYLOAD="{\"title\":\"${PR_TITLE}\",\"body\":\"${PR_BODY}\",\"head\":\"${BRANCH_NAME}\",\"base\":\"${INPUT_TARGET_SYNC_BRANCH}\"}"
        
        # For debugging
        echo "${JSON_PAYLOAD}" > /tmp/pr_payload.json
        
        # Create PR using GitHub API
        PR_RESPONSE=$(curl -s -X POST \
            -H "Authorization: token ${INPUT_TARGET_REPO_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls" \
            -d "${JSON_PAYLOAD}")
        
        # Check if PR was created successfully
        if echo "${PR_RESPONSE}" | grep -q "\"number\""; then
            PR_NUMBER=$(echo "${PR_RESPONSE}" | grep -o '\"number\":[^,]*' | cut -d ':' -f 2)
            write_out "0" "Successfully created PR #${PR_NUMBER} for changes."
            
            # Option to automatically delete branch after PR creation
            # First switch back to original branch (target sync branch, main, or master)
            git checkout "${INPUT_TARGET_SYNC_BRANCH}" || git checkout main || git checkout master
            
            # Delete local branch
            git branch -D "${BRANCH_NAME}"
            
            # Delete remote branch
            git push origin --delete "${BRANCH_NAME}"
            DELETE_STATUS=$?
            
            if [ "${DELETE_STATUS}" = 0 ]; then
                write_out "0" "Successfully deleted branch ${BRANCH_NAME} after PR creation."
            else
                write_out "0" "PR created successfully, but failed to delete branch ${BRANCH_NAME}."
            fi
            
            write_out "g" 'SUCCESS\n'
        else
            write_out "1" "Failed to create PR. API response: ${PR_RESPONSE}"
        fi
    else
        write_out "0" "Changes pushed to branch ${BRANCH_NAME}. Please create a PR manually."
        write_out "g" 'SUCCESS\n'
    fi
}
